#!/usr/bin/env python3
"""Verify repository dependency pins are at least 72 hours old; never install code."""

import argparse
import concurrent.futures
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
import functools
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import urllib.parse
import urllib.request
import urllib.error

from mcp_snapshot import validate_snapshot

ROOT = Path(__file__).resolve().parents[1]


def timestamp(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Use a timestamp with an explicit timezone")
    return parsed.astimezone(timezone.utc)


def require_mature(label, published, cutoff):
    if published > cutoff:
        raise ValueError(f"{label}: published {published.isoformat()}, after {cutoff.isoformat()}")


def request(url, method="GET"):
    headers = {"User-Agent": "agent-skills-dependency-age"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if urllib.parse.urlparse(url).hostname == "api.github.com" and token:
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers, method=method), timeout=60)


@functools.lru_cache(maxsize=None)
def fetch_json(url):
    if (urllib.parse.urlparse(url).hostname == "api.github.com"
            and not (os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"))
            and shutil.which("gh")):
        # Reuse the user's authenticated GitHub CLI without printing its token.
        return json.loads(subprocess.check_output(["gh", "api", "--cache", "1h", url], stderr=subprocess.PIPE))
    with request(url) as response:
        return json.load(response)


def npm_check(name, versions, cutoff):
    data = fetch_json("https://registry.npmjs.org/" + urllib.parse.quote(name, safe=""))
    for version, artifacts in versions.items():
        dist = data["versions"][version]["dist"]
        for resolved, integrity in artifacts:
            if resolved != dist["tarball"] or integrity != dist.get("integrity"):
                raise ValueError(f"npm {name}@{version}: tarball or integrity differs from registry release")
        require_mature(f"npm {name}@{version}", timestamp(data["time"][version]), cutoff)


def action_check(repo, sha, tag, cutoff):
    base = f"https://api.github.com/repos/{repo}"
    release = fetch_json(base + "/releases/tags/" + tag)
    if release["draft"] or release["prerelease"]:
        raise ValueError(f"{repo}@{tag}: use a stable published release")
    require_mature(f"{repo}@{tag}", timestamp(release["published_at"]), cutoff)
    target = fetch_json(base + "/git/ref/tags/" + tag)["object"]
    while target["type"] == "tag":
        target = fetch_json(target["url"])["object"]
    if target["type"] != "commit" or target["sha"] != sha:
        raise ValueError(f"{repo}@{sha}: does not match release {tag}")
    commit = fetch_json(base + "/commits/" + sha)
    require_mature(f"{repo} commit {sha}", timestamp(commit["commit"]["committer"]["date"]), cutoff)


def maven_check(group, artifact, version, cutoff):
    path = group.replace(".", "/") + f"/{artifact}/{version}/{artifact}-{version}.pom"
    repositories = ["https://repo.maven.apache.org/maven2/", "https://dl.google.com/dl/android/maven2/"]
    modified = None
    for repository in repositories:
        try:
            with request(repository + path, "HEAD") as response:
                modified = response.headers.get("Last-Modified")
            break
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise ValueError(f"{group}:{artifact}:{version}: {error}") from error
    if not modified:
        raise ValueError(f"{group}:{artifact}:{version}: repository has no publication evidence")
    require_mature(f"{group}:{artifact}:{version}", parsedate_to_datetime(modified), cutoff)


def gradle_check(path, cutoff):
    properties = dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)
    version = re.search(r"gradle-(\d+\.\d+\.\d+)-bin.zip$", properties["distributionUrl"])[1]
    release = next(item for item in fetch_json("https://services.gradle.org/versions/all") if item["version"] == version)
    built = datetime.strptime(release["buildTime"], "%Y%m%d%H%M%S%z")
    require_mature(f"Gradle {version}", built, cutoff)
    with request(f"https://services.gradle.org/distributions/gradle-{version}-bin.zip.sha256") as response:
        expected = response.read().decode().strip()
    if properties.get("distributionSha256Sum") != expected:
        raise ValueError(f"{path}: missing or incorrect distribution checksum")
    with request(f"https://services.gradle.org/distributions/gradle-{version}-wrapper.jar.sha256") as response:
        expected = response.read().decode().strip()
    if hashlib.sha256(path.with_name("gradle-wrapper.jar").read_bytes()).hexdigest() != expected:
        raise ValueError(f"{path}: wrapper JAR differs from the official {version} checksum")


def collect(root, cutoff):
    """Only version-controlled files count; local tool-generated caches are excluded."""
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    npm, actions, maven = {}, set(), set()
    for filename in filter(None, files):
        path = root / filename
        if path.name == "package-lock.json":
            for location, package in json.loads(path.read_text())["packages"].items():
                if location:
                    name = location.rsplit("node_modules/", 1)[-1]
                    if not package.get("resolved", "").startswith("https://registry.npmjs.org/"):
                        raise ValueError(f"{filename}: unsupported package source for {name}")
                    if package.get("name", name) != name:
                        raise ValueError(f"{filename}: npm aliases are not supported: {name}")
                    integrity = package.get("integrity")
                    if not integrity:
                        raise ValueError(f"{filename}: missing integrity for {name}")
                    npm.setdefault(name, {}).setdefault(package["version"], set()).add((package["resolved"], integrity))
        elif filename.startswith(".github/workflows/") and path.suffix in (".yml", ".yaml"):
            for line in path.read_text().splitlines():
                match = re.search(r"uses:\s+([^\s]+)", line)
                if not match or match[1].startswith("./"):
                    continue
                pin = re.fullmatch(r"([^@]+)@([0-9a-f]{40})", match[1])
                tag = re.search(r"#\s*(v\d+\.\d+\.\d+)\s*$", line)
                if not pin or not tag:
                    raise ValueError(f"{filename}: pin actions to a full SHA with an exact release comment")
                actions.add(("/".join(pin[1].split("/")[:2]), pin[2], tag[1]))
        elif path.name.endswith(".gradle.kts"):
            text = path.read_text()
            maven.update(re.findall(r'"([\w.\-]+):([\w.\-]+):(\d+(?:\.\d+){1,3}(?:-(?:jre|android))?)"', text))
            for version in re.findall(r'kotlin\("jvm"\) version "([\d.]+)"', text):
                maven.add(("org.jetbrains.kotlin", "kotlin-gradle-plugin", version))
            for version in re.findall(r'id\("com.android.application"\) version "([\d.]+)"', text):
                maven.add(("com.android.tools.build", "gradle", version))
    if (root / ".mcp.json").exists():
        _, before = validate_snapshot(root)
        require_mature("MCP transitive resolution cutoff", timestamp(before), cutoff)
    return npm, actions, maven


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--now", help="UTC timestamp for a reproducible audit")
    parser.add_argument("--maven-inventory", type=Path, action="append", default=[],
                        help="Also check resolved Maven modules and query OSV advisories")
    args = parser.parse_args()
    now = timestamp(args.now) if args.now else datetime.now(timezone.utc)
    cutoff = now - timedelta(days=3)
    npm, actions, maven = collect(ROOT, cutoff)
    for inventory in args.maven_inventory:
        for module in json.loads(inventory.read_text()):
            if not module["group"] or module["version"] == "unspecified":
                raise ValueError(f"{inventory}: contains project IDs; regenerate with dependency-inventory.gradle")
            maven.add((module["group"], module["name"], module["version"]))
    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        checks = [pool.submit(npm_check, name, versions, cutoff) for name, versions in npm.items()]
        checks += [pool.submit(action_check, *action, cutoff) for action in actions]
        checks += [pool.submit(maven_check, *module, cutoff) for module in maven]
        checks += [pool.submit(gradle_check, path, cutoff) for path in ROOT.glob("tests/kotlin-sdk/*/gradle/wrapper/gradle-wrapper.properties")]
        for check in concurrent.futures.as_completed(checks):
            try:
                check.result()
            except Exception as error:
                failures.append(str(error))
    if args.maven_inventory:
        modules = sorted(maven)
        queries = [{"package": {"ecosystem": "Maven", "name": group + ":" + artifact}, "version": version}
                   for group, artifact, version in modules]
        body = json.dumps({"queries": queries}).encode()
        req = urllib.request.Request("https://api.osv.dev/v1/querybatch", data=body,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as response:
            findings = json.load(response)["results"]
        for module, finding in zip(modules, findings):
            for advisory in finding.get("vulns", []):
                failures.append(":".join(module) + ": " + advisory["id"])
    if failures:
        for failure in sorted(failures):
            print("FAIL:", failure)
        return 1
    print(f"Dependency age OK: {sum(map(len, npm.values()))} npm versions, {len(actions)} actions, {len(maven)} Maven pins; cutoff {cutoff.isoformat()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
