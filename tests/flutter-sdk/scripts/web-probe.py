#!/usr/bin/env python3
"""Flutter Web build-mode and hosting probes for skills/flutter-sdk.

    python3 tests/flutter-sdk/scripts/web-probe.py --line 5.2 [--probe ID]... [--skip-manual]

Builds integration_test/web/probe_app.dart with `flutter build web --release` (dart2js,
and dart2wasm with --wasm) in a use-version.py copy of minimal_app pinned to <line>,
serves each bundle from a local http.server with the headers a probe needs, loads it in
headless Chrome through ChromeDriver, and asserts the transcript the app publishes in
`globalThis.dittoProbe`. One function per probe ID (PROBES below); each prints
`PROBE <id>: PASS|FAIL <outcome>`.

  web_default_build       dart2js release bundle opens Ditto, writes and reads
  web_wasm_build          --wasm release bundle runs as dart2wasm and does the same
  web_no_coop_coep        both bundles without COOP/COEP headers (not cross-origin
                          isolated), and the wasm bundle with them
  web_csp                 a Content-Security-Policy with and without 'wasm-unsafe-eval'
  web_base_href           --base-href /app/: Ditto.init() with defaults, then the
                          relative wasmShimUrl fix
  web_reload_persistence  a document written before a page reload, read after it
  web_large_result_jank   5,000 documents, then SELECT * and SELECT ... LIMIT 50 timed in
                          Dart, with the longest task and longest frame gap the page saw

--skip-manual skips web_large_result_jank, whose numbers are a measurement recorded by
hand (web-results/), not an assertion that holds on every runner.

The license comes from DITTO_OFFLINE_LICENSE (environment, else the gitignored repo-root
.env, parsed like run-fixture.sh). It reaches Flutter only through
--dart-define-from-file: a mode-600 temporary file deleted on exit, not an argument of
the flutter command. The compiled bundles embed it, so the whole fixture copy (every build/
directory, .dart_tool) is deleted before it exits, and printed browser logs have the
license redacted.

ChromeDriver: a ChromeDriver already answering /status on 127.0.0.1:4444 is reused;
otherwise $CHROMEDRIVER (default `chromedriver` on PATH) is started on a free port and
must report ready within 10 s. FLUTTER and PYTHON select the executables as in
run-fixture.sh. Every flutter build is bounded by WEB_PROBE_BUILD_TIMEOUT seconds
(default 900) and every page load by 90 s.
"""

from __future__ import annotations

import argparse
import contextlib
import functools
import http.server
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

HARNESS = Path(__file__).resolve().parents[1]
REPO_ROOT = HARNESS.parents[1]
TARGET = "integration_test/web/probe_app.dart"
LOAD_TIMEOUT = 90.0

COOP_COEP = {
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
}
# Everything a self-hosted (--no-web-resources-cdn) Flutter bundle loads is same-origin.
CSP_BASE = ("default-src 'self'; script-src 'self'{wasm}; style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; "
            "worker-src 'self' blob:")

# Runs before any page script (CDP Page.addScriptToEvaluateOnNewDocument): long tasks
# and requestAnimationFrame timestamps, both on the performance.now() clock.
PERF_SCRIPT = """
window.__probePerf = {longTasks: [], frames: [], cspViolations: []};
document.addEventListener('securitypolicyviolation', (e) => {
  window.__probePerf.cspViolations.push(
    [e.effectiveDirective, e.blockedURI, (e.sourceFile || '').split('/').pop()]);
});
try {
  new PerformanceObserver((list) => {
    for (const e of list.getEntries()) window.__probePerf.longTasks.push([e.startTime, e.duration]);
  }).observe({type: 'longtask', buffered: true});
} catch (e) {}
(function tick(t) {
  window.__probePerf.frames.push(t);
  requestAnimationFrame(tick);
})(performance.now());
"""


class ProbeFailure(AssertionError):
    pass


# --- license and defines ------------------------------------------------------------


def parse_env_file(text: str) -> dict[str, str]:
    """The run-fixture.sh .env parser: KEY=value lines, split on the first "=",
    leading whitespace, one pair of surrounding quotes and a CR stripped."""
    values: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.rstrip("\r")
        key, sep, value = line.partition("=")
        if not sep or not key or not (key[0].isupper() or key[0] == "_"):
            continue
        if not all(c.isupper() or c.isdigit() or c == "_" for c in key):
            continue
        value = value.lstrip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values.setdefault(key, value)
    return values


def offline_license(environ: dict[str, str] | None = None, env_file: Path | None = None) -> str:
    environ = os.environ if environ is None else environ
    if environ.get("DITTO_OFFLINE_LICENSE"):
        return environ["DITTO_OFFLINE_LICENSE"]
    env_file = REPO_ROOT / ".env" if env_file is None else env_file
    if env_file.is_file():
        value = parse_env_file(env_file.read_text()).get("DITTO_OFFLINE_LICENSE", "")
        if value:
            return value
    raise SystemExit("DITTO_OFFLINE_LICENSE is not set. Copy .env-sample to .env at the repo root.")


@contextlib.contextmanager
def defines_file(defines: dict[str, str]):
    """A mode-600 JSON defines file for --dart-define-from-file, deleted on exit."""
    descriptor, name = tempfile.mkstemp(prefix="ditto-defines.", suffix=".json")
    path = Path(name)
    try:
        os.chmod(path, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(defines, output)
        yield path
    finally:
        path.unlink(missing_ok=True)


def redact(text: str, secret: str) -> str:
    return text.replace(secret, "<redacted>") if secret else text


# --- builds -------------------------------------------------------------------------


def child_environment(environ: dict[str, str] | None = None) -> dict[str, str]:
    """The environment for flutter and the fixture scripts, without any DITTO_* variable.

    Ditto reads DITTO_* variables from its process environment as system parameters,
    and the apps get everything they need (the license included) from the defines file.
    """
    environ = os.environ if environ is None else environ
    return {key: value for key, value in environ.items() if not key.startswith("DITTO_")}


def flutter_command() -> list[str]:
    flutter = os.environ.get("FLUTTER")
    if flutter:
        return [flutter]
    return ["fvm", "flutter"]


def prepare_workdir(line: str) -> Path:
    python = os.environ.get("PYTHON", sys.executable)
    result = subprocess.run([python, str(HARNESS / "scripts/use-version.py"), "minimal_app", line],
                            stdout=subprocess.PIPE, text=True, check=True, env=child_environment())
    return Path(result.stdout.strip().splitlines()[-1])


def build_args(variant: str, out: Path, defines: Path) -> list[str]:
    """The `flutter build web` arguments for one bundle variant."""
    args = ["build", "web", "--release", "-t", TARGET, "--no-web-resources-cdn",
            f"--dart-define-from-file={defines}", "-o", str(out)]
    if variant in ("wasm",):
        args.append("--wasm")
    if variant == "js-app":
        args += ["--base-href", "/app/"]
    return args


def remove_web_build_output(workdir: Path) -> None:
    """Deletes what Flutter web builds leave in a fixture copy besides -o: the
    intermediate main.dart.js (with every define, the license included) under
    .dart_tool/flutter_build/<hash>/, build/web, and the incremental-compile caches
    build/*.cache.dill.track.dill, which embed the defines too."""
    shutil.rmtree(workdir / ".dart_tool" / "flutter_build", ignore_errors=True)
    shutil.rmtree(workdir / "build" / "web", ignore_errors=True)
    for cache in (workdir / "build").glob("*.cache.dill.track.dill"):
        cache.unlink(missing_ok=True)


def remove_fixture_copy(workdir: Path) -> None:
    """Deletes a use-version.py fixture copy whole. Every build in it embeds the
    defines, the license included (build/, .dart_tool/, generated platform config),
    so the scripts that build with the license delete it when they end; the next
    run rebuilds from scratch. Refuses a path that is not <root>/<line>/<fixture>
    under a flutter-fixture-<user> root."""
    if not workdir.parent.parent.name.startswith("flutter-fixture-"):
        print(f"not deleting {workdir}: not a use-version.py fixture copy", file=sys.stderr)
        return
    for attempt in range(2):
        try:
            shutil.rmtree(workdir)
            return
        except FileNotFoundError:
            return
        except OSError as error:
            if attempt:
                print(f"::warning::could not delete the fixture copy {workdir}, which embeds the license: {error}",
                      file=sys.stderr)
            else:
                time.sleep(5)  # Windows can hold a just-exited app's files open.


def exit_on_sigterm() -> None:
    """SIGTERM raises SystemExit, so `finally` blocks (and the copy's deletion) run."""
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(128 + signum))


class Builds:
    """Builds bundle variants on demand, once each; deletes them all on close."""

    def __init__(self, workdir: Path, defines: Path):
        self.workdir = workdir
        self.defines = defines
        self.root = workdir / "build" / "web-probe"
        self.built: dict[str, Path] = {}

    def get(self, variant: str) -> Path:
        if variant not in self.built:
            out = self.root / variant
            timeout = float(os.environ.get("WEB_PROBE_BUILD_TIMEOUT", "900"))
            print(f"== flutter build web ({variant})", flush=True)
            subprocess.run(flutter_command() + build_args(variant, out, self.defines),
                           cwd=self.workdir, check=True, timeout=timeout,
                           stdout=sys.stderr, env=child_environment())
            self.built[variant] = out
        return self.built[variant]

    def close(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)
        remove_web_build_output(self.workdir)


# --- serving ------------------------------------------------------------------------


class _Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".mjs": "text/javascript",
                      ".js": "text/javascript", ".json": "application/json"}

    def __init__(self, *args, prefix: str, headers: dict[str, str], **kwargs):
        self._prefix = prefix
        self._extra = headers
        super().__init__(*args, **kwargs)

    def translate_path(self, path: str) -> str:
        # Serve the bundle only below the mount prefix; everything else is a 404.
        bare = path.split("?", 1)[0].split("#", 1)[0]
        if not bare.startswith(self._prefix):
            return str(Path(self.directory) / "__outside_mount__")
        return super().translate_path("/" + bare[len(self._prefix):])

    def end_headers(self) -> None:
        for name, value in self._extra.items():
            self.send_header(name, value)
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args) -> None:
        pass


@contextlib.contextmanager
def serve(directory: Path, prefix: str = "/", headers: dict[str, str] | None = None):
    """Serves [directory] at http://127.0.0.1:<port><prefix>; yields that URL."""
    if not (prefix.startswith("/") and prefix.endswith("/")):
        raise ValueError("prefix must start and end with /")
    handler = functools.partial(_Handler, directory=str(directory), prefix=prefix,
                                headers=dict(headers or {}))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_address[1]}{prefix}"
    finally:
        server.shutdown()
        server.server_close()


# --- ChromeDriver -------------------------------------------------------------------


def _request(method: str, url: str, body: object | None = None, timeout: float = 30.0) -> dict:
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=data, method=method,
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read() or b"{}")


def chromedriver_ready(base: str) -> bool:
    try:
        return bool(_request("GET", f"{base}/status", timeout=2)["value"].get("ready"))
    except (OSError, ValueError, KeyError, urllib.error.URLError):
        return False


def _free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


@contextlib.contextmanager
def chromedriver():
    """Yields a ChromeDriver base URL: :4444 if one answers there, else a new one."""
    if chromedriver_ready("http://127.0.0.1:4444"):
        yield "http://127.0.0.1:4444"
        return
    executable = os.environ.get("CHROMEDRIVER", "chromedriver")
    port = _free_port()
    try:
        process = subprocess.Popen([executable, f"--port={port}"], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
    except OSError as error:
        raise SystemExit(f"cannot start ChromeDriver ({executable}): {error}") from error
    base = f"http://127.0.0.1:{port}"
    try:
        deadline = time.monotonic() + 10
        while not chromedriver_ready(base):
            if process.poll() is not None or time.monotonic() > deadline:
                raise SystemExit(f"ChromeDriver ({executable}) did not report ready on {base}")
            time.sleep(0.2)
        yield base
    finally:
        process.terminate()
        with contextlib.suppress(subprocess.TimeoutExpired):
            process.wait(timeout=10)
        if process.poll() is None:
            process.kill()


class Browser:
    """A headless Chrome session through the W3C WebDriver HTTP API."""

    def __init__(self, base: str):
        capabilities = {"capabilities": {"alwaysMatch": {
            "browserName": "chrome",
            "goog:loggingPrefs": {"browser": "ALL"},
            "goog:chromeOptions": {"args": ["--headless=new", "--window-size=1280,800",
                                            "--no-first-run", "--no-default-browser-check"]},
        }}}
        value = _request("POST", f"{base}/session", capabilities, timeout=60)["value"]
        self.url = f"{base}/session/{value['sessionId']}"
        self.version = value["capabilities"].get("browserVersion", "?")
        _request("POST", f"{self.url}/goog/cdp/execute",
                 {"cmd": "Page.addScriptToEvaluateOnNewDocument", "params": {"source": PERF_SCRIPT}})

    def navigate(self, url: str) -> None:
        _request("POST", f"{self.url}/url", {"url": url}, timeout=LOAD_TIMEOUT)

    def script(self, source: str) -> object:
        return _request("POST", f"{self.url}/execute/sync", {"script": source, "args": []})["value"]

    def console(self) -> list[str]:
        try:
            entries = _request("POST", f"{self.url}/se/log", {"type": "browser"})["value"]
        except (OSError, urllib.error.URLError):
            return []
        return [f"{e.get('level')}: {e.get('message')}" for e in entries]

    def quit(self) -> None:
        with contextlib.suppress(OSError, urllib.error.URLError):
            _request("DELETE", self.url)

    def load(self, url: str, timeout: float = LOAD_TIMEOUT) -> dict:
        """Loads [url] and waits for the probe app's transcript; status "timeout"
        when the app never publishes one (main() did not run to the end)."""
        self.navigate(url)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            published = self.script("return window.dittoProbe || null;")
            if published:
                return json.loads(published)
            time.sleep(0.25)
        return {"status": "timeout", "lines": []}


# --- transcript and timing helpers ----------------------------------------------------


def transcript_value(transcript: dict, key: str) -> str | None:
    """The value of the first `key: value` line, or None."""
    for line in transcript.get("lines", []):
        name, sep, value = line.partition(": ")
        if sep and name == key:
            return value
    return None


def parse_window(value: str) -> tuple[int, int, float, float]:
    """`items=5000 ms=812 window=1234.5-2046.7` -> (5000, 812, 1234.5, 2046.7)."""
    fields = dict(part.split("=", 1) for part in value.split())
    start, end = fields["window"].split("-")
    return int(fields["items"]), int(fields["ms"]), float(start), float(end)


def longest_task_in(tasks: list[list[float]], start: float, end: float) -> float:
    """The longest long task that overlaps [start, end], in ms (0 if none)."""
    overlapping = [d for (s, d) in tasks if s < end and s + d > start]
    return max(overlapping, default=0.0)


def longest_frame_gap_in(frames: list[float], start: float, end: float) -> float:
    """The longest interval between consecutive animation frames that overlaps
    [start, end], in ms (0 if fewer than two frames)."""
    gaps = [b - a for a, b in zip(frames, frames[1:]) if a < end and b > start]
    return max(gaps, default=0.0)


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise ProbeFailure(message)


def expect_smoke(transcript: dict, compiler: str, isolated: bool) -> None:
    expect(transcript.get("status") == "done", f"status {transcript.get('status')}: {transcript}")
    expect(transcript_value(transcript, "compiler") == compiler, f"compiler: {transcript}")
    expect(transcript_value(transcript, "release") == "true", f"release: {transcript}")
    expect(transcript_value(transcript, "crossOriginIsolated") == str(isolated).lower(),
           f"crossOriginIsolated: {transcript}")
    expect(transcript_value(transcript, "read-back make") == "Toyota", f"read-back: {transcript}")
    # The probe app imports dart:io and still compiled; reading Platform throws.
    expect((transcript_value(transcript, "dart:io Platform") or "").startswith("UnsupportedError"),
           f"dart:io Platform: {transcript}")


def expect_wasm_defect(transcript: dict, isolated: bool) -> None:
    """The dart2wasm bundle, as observed on 5.1.0 and 5.2.0: Ditto initializes and
    opens, but every query result after the first resolves to the first one (the web
    bridge's pointer registry keys on Object.hashAll([JSString, JSNumber]), and under
    dart2wasm every JS value's hashCode is 0, strings and numbers alike), so the second
    INSERT reports the first INSERT's mutated IDs and the SELECT returns no items."""
    expect(transcript.get("status") == "done", f"status {transcript.get('status')}: {transcript}")
    expect(transcript_value(transcript, "compiler") == "dart2wasm", f"compiler: {transcript}")
    expect(transcript_value(transcript, "crossOriginIsolated") == str(isolated).lower(),
           f"crossOriginIsolated: {transcript}")
    expect(transcript_value(transcript, "js hashCode") == "a=0 b=0 1=0 2=0",
           f"hashCode: {transcript}")
    expect(transcript_value(transcript, "insert mutated") == "[blue-toyota]", f"insert: {transcript}")
    expect(transcript_value(transcript, "literal insert mutated") == "[blue-toyota]",
           f"second insert: {transcript}")
    expect(transcript_value(transcript, "select items") == "0", f"select: {transcript}")


# --- probes -------------------------------------------------------------------------


class Context:
    def __init__(self, builds: Builds, browser: Browser, pin: str, secret: str):
        self.builds = builds
        self.browser = browser
        self.pin = pin
        self.secret = secret

    def load(self, variant: str, query: str = "", prefix: str = "/",
             headers: dict[str, str] | None = None, timeout: float = LOAD_TIMEOUT) -> dict:
        with serve(self.builds.get(variant), prefix, headers) as url:
            return self.browser.load(url + query, timeout)


def web_default_build(ctx: Context) -> str:
    transcript = ctx.load("js")
    expect_smoke(transcript, "dart2js", isolated=False)
    expect(transcript_value(transcript, "SDK version") == ctx.pin, f"version: {transcript}")
    return "dart2js release bundle: init ok, write and read back ok"


def web_wasm_build(ctx: Context) -> str:
    transcript = ctx.load("wasm")
    expect_wasm_defect(transcript, isolated=False)
    return ("--wasm release bundle runs as dart2wasm; init and open ok, but the second "
            "INSERT reports the first one's mutated IDs [blue-toyota] and SELECT * returns "
            "0 items (every JS value's hashCode is 0 under dart2wasm)")


def web_no_coop_coep(ctx: Context) -> str:
    expect_smoke(ctx.load("js"), "dart2js", isolated=False)
    expect_wasm_defect(ctx.load("wasm"), isolated=False)
    expect_wasm_defect(ctx.load("wasm", headers=COOP_COEP), isolated=True)
    return ("no COOP/COEP: dart2js works (crossOriginIsolated=false); dart2wasm "
            "initializes and opens with or without COOP same-origin + COEP require-corp "
            "(crossOriginIsolated false / true), with the same wrong query results either way")


def web_csp(ctx: Context) -> str:
    outcomes = []
    for variant in ("js", "wasm"):
        allowed = ctx.load(variant, headers={
            "Content-Security-Policy": CSP_BASE.format(wasm=" 'wasm-unsafe-eval'")})
        compiler = "dart2wasm" if variant == "wasm" else "dart2js"
        if variant == "wasm":
            expect_wasm_defect(allowed, isolated=False)
        else:
            expect_smoke(allowed, compiler, isolated=False)
        ctx.browser.console()  # drop earlier entries
        blocked = ctx.load(variant, headers={"Content-Security-Policy": CSP_BASE.format(wasm="")},
                           timeout=30)
        # No transcript at all: the app's main() never ran.
        expect(blocked == {"status": "timeout", "lines": []},
               f"{variant} without 'wasm-unsafe-eval': {blocked}")
        errors = [e for e in ctx.browser.console() if e.startswith("SEVERE")]
        violations = (ctx.browser.script("return window.__probePerf.cspViolations;") or [])
        expect(bool(errors) and "CompileError" in errors[0], f"first console error: {errors[:1]}")
        expect(bool(violations) and violations[0][:2] == ["script-src", "wasm-eval"],
               f"CSP violations: {violations}")
        outcomes.append(f"{compiler}: with 'wasm-unsafe-eval' ok; without it no transcript "
                        f"(main() never ran), first console error {errors[0][:200]!r}, "
                        f"first CSP violation {violations[0]} of {len(violations)}")
    return "; ".join(outcomes)


def web_base_href(ctx: Context) -> str:
    default = ctx.load("js-app", prefix="/app/")
    expect(default.get("status") == "error", f"default init under /app/: {default}")
    error = transcript_value(default, "error") or ""
    expect("Failed to initialize Ditto WebAssembly" in error, f"default init error: {default}")
    fixed = ctx.load("js-app", query="?shim=relative", prefix="/app/")
    expect_smoke(fixed, "dart2js", isolated=False)
    return f"defaults under /app/: error: {error}; relative wasmShimUrl: ok"


def web_reload_persistence(ctx: Context) -> str:
    with serve(ctx.builds.get("js")) as url:
        before = ctx.browser.load(url + "?mode=reload-write")
        expect(transcript_value(before, "documents before reload") == "1", f"write: {before}")
        after = ctx.browser.load(url + "?mode=reload-read")
    expect(after.get("status") == "done", f"read: {after}")
    count = transcript_value(after, "documents after reload")
    expect(count == "0", f"after reload: {after}")
    return f"1 document before the reload, {count} after it (in-memory store)"


def web_large_result_jank(ctx: Context) -> str:
    # dart2js only: under dart2wasm the SELECT returns 0 items (expect_wasm_defect).
    results = []
    for variant, compiler in (("js", "dart2js"),):
        with serve(ctx.builds.get(variant)) as url:
            transcript = ctx.browser.load(url + "?mode=jank")
            perf = ctx.browser.script("return window.__probePerf;") or {}
        expect(transcript.get("status") == "done", f"{variant} jank: {transcript}")
        expect(transcript_value(transcript, "inserted") == "5000", f"insert: {transcript}")
        tasks = perf.get("longTasks", [])
        results.append(f"{compiler}: {len(tasks)} long task(s) on the page in all, longest "
                       f"{max((d for _, d in tasks), default=0):.0f} ms")
        for label, expected in (("select all", 5000), ("select all + values", 5000),
                                ("select limit 50 + values", 50)):
            items, ms, start, end = parse_window(transcript_value(transcript, label) or "")
            expect(items == expected, f"{label}: {items} items")
            task = longest_task_in(tasks, start, end)
            gap = longest_frame_gap_in(perf.get("frames", []), start, end)
            results.append(f"{compiler} {label}: execute {ms} ms, longest task {task:.0f} ms, "
                           f"longest frame gap {gap:.0f} ms")
    return "; ".join(results)


PROBES = {
    "web_default_build": web_default_build,
    "web_wasm_build": web_wasm_build,
    "web_no_coop_coep": web_no_coop_coep,
    "web_csp": web_csp,
    "web_base_href": web_base_href,
    "web_reload_persistence": web_reload_persistence,
    "web_large_result_jank": web_large_result_jank,
}
MANUAL = {"web_large_result_jank"}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--line", required=True)
    parser.add_argument("--probe", action="append", choices=sorted(PROBES))
    parser.add_argument("--skip-manual", action="store_true")
    args = parser.parse_args(argv)

    lines = json.loads((HARNESS / "versions.json").read_text())["lines"]
    if args.line not in lines or args.line == "4.14":
        parser.error(f"--line must be one of {', '.join(k for k in lines if k != '4.14')}")
    pin = lines[args.line]
    selected = args.probe or list(PROBES)
    if args.skip_manual:
        selected = [name for name in selected if name not in MANUAL]

    secret = offline_license()
    exit_on_sigterm()
    workdir = prepare_workdir(args.line)
    try:
        return run_probes(workdir, selected, pin, secret)
    finally:
        remove_fixture_copy(workdir)


def run_probes(workdir: Path, selected: list[str], pin: str, secret: str) -> int:
    defines = {"DITTO_LICENSE": secret, "DITTO_VERSION": pin, "DITTO_PLATFORM": "web"}
    failures = 0
    with defines_file(defines) as path, chromedriver() as base:
        builds = Builds(workdir, path)
        browser = None
        try:
            browser = Browser(base)
            print(f"== ditto_live {pin}, Chrome {browser.version}", flush=True)
            ctx = Context(builds, browser, pin, secret)
            for name in selected:
                try:
                    outcome = PROBES[name](ctx)
                    print(f"PROBE {name}: PASS {outcome}", flush=True)
                except (ProbeFailure, subprocess.SubprocessError, OSError) as error:
                    failures += 1
                    print(f"PROBE {name}: FAIL {redact(str(error), secret)}", flush=True)
                    problems = [e for e in browser.console()
                                if e.startswith(("WARNING", "SEVERE"))]
                    for entry in problems[-10:]:
                        print(f"  console {redact(entry, secret)}", flush=True)
        finally:
            if browser is not None:
                browser.quit()
            builds.close()
    print(f"== {len(selected) - failures}/{len(selected)} probes passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
