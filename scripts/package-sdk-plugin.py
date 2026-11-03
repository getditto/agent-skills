#!/usr/bin/env python3
"""Generate per-SDK-plugin host manifests and self-contained installation archives.

One script serves every SDK plugin wrapper under plugins/. Select the plugin with
--plugin (default: ditto-swift, which keeps the original Swift command lines working).
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"

# Per-plugin identity that is not derivable from the canonical Claude manifest. Add a
# row when a new SDK plugin lands; everything else (version, description, author,
# keywords) is read from plugins/<name>/.claude-plugin/plugin.json.
PLUGINS = {
    "ditto-swift": {
        "skill": "swift-sdk",
        "display_name": "Ditto Swift",
        "short_description": "Build and troubleshoot Ditto Swift apps for Apple platforms.",
        "homepage": "https://docs.ditto.live/sdk/latest/install-guides/swift",
        "default_prompt": [
            "Build a runnable SwiftUI app with Ditto and a diagnostics screen.",
            "Integrate Ditto into this existing Swift app.",
            "Diagnose why my Swift app writes locally but does not sync."],
        "install_doc": "docs/install-swift.md",
        "extra_docs": ["docs/swift-workflow-verification.md"],
    },
    "ditto-kotlin": {
        "skill": "kotlin-sdk",
        "display_name": "Ditto Kotlin",
        "short_description": "Integrate and troubleshoot the Ditto Kotlin SDK on Android and the JVM.",
        "homepage": "https://docs.ditto.live/sdk/latest/install-guides/kotlin",
        "default_prompt": [
            "Integrate Ditto into this Android app with a ViewModel-backed observer.",
            "Generate a runnable Gradle project that syncs a collection with Ditto.",
            "Diagnose why my Kotlin store observer stopped delivering updates."],
        "install_doc": "docs/install-kotlin.md",
        "extra_docs": [],
    },
}

NAME = "ditto-swift"
PLUGIN = ROOT / "plugins" / NAME
META = PLUGINS[NAME]


def configure(name):
    """Select the plugin every other function operates on."""
    global NAME, PLUGIN, META
    if name not in PLUGINS:
        raise ValueError(f"Unknown plugin {name!r}; known: {', '.join(sorted(PLUGINS))}")
    NAME, PLUGIN, META = name, ROOT / "plugins" / name, PLUGINS[name]


def write(path, content):
    with path.open("w", encoding="utf-8", newline="\n") as output:
        output.write(content)


def encoded(value):
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def update_catalog(relative, default):
    """Own this plugin's entry while preserving plugins added by other SDK PRs."""
    path = ROOT / relative
    existing = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
    entries = list(existing.get("plugins", []))
    # Replace in place so the catalog order does not depend on which plugin synced last;
    # otherwise `--check` for one plugin fails right after `--sync-manifests` for another.
    position = next((i for i, entry in enumerate(entries) if entry["name"] == NAME), None)
    if position is None:
        entries.extend(default["plugins"])
    else:
        entries[position:position + 1] = default["plugins"]
    return {**default, **existing, "plugins": entries}


def manifests():
    legacy = json.loads((PLUGIN / ".claude-plugin/plugin.json").read_text(encoding="utf-8"))
    identity = {key: legacy[key] for key in ("name", "version", "description", "author", "license", "keywords")}
    identity.update(repository="https://github.com/getditto/agent-skills", homepage=META["homepage"])
    interface = {"displayName": META["display_name"], "shortDescription": META["short_description"],
                 "developerName": "Ditto", "category": "Developer Tools", "capabilities": ["Read", "Write"],
                 "websiteURL": "https://ditto.com", "defaultPrompt": list(META["default_prompt"])}
    portable = {"$schema": SCHEMA, **identity, "extensions": {"com.openai": {"interface": interface}}}
    codex = {**identity, "skills": "./skills/", "interface": interface}
    cursor = {**identity, "skills": "./skills/"}
    gemini = {"name": identity["name"], "version": identity["version"], "description": identity["description"]}
    source = f"./plugins/{NAME}"
    entry = {"name": identity["name"], "source": source, "description": identity["description"]}
    catalog = {"name": "ditto-plugins", "owner": identity["author"], "plugins": [entry]}
    # The catalog is shared by every SDK plugin, so its display name is the vendor's.
    codex_catalog = {"name": "ditto-plugins", "interface": {"displayName": "Ditto"}, "plugins": [{
        "name": identity["name"], "source": {"source": "local", "path": source},
        "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}, "category": "Developer Tools",
    }]}
    claude_catalog = json.loads((ROOT / ".claude-plugin/marketplace.json").read_text(encoding="utf-8"))
    for entry in claude_catalog["plugins"]:
        if entry["name"] == identity["name"]:
            entry.update(version=identity["version"], description=identity["description"], author=identity["author"])
    return {
        ".claude-plugin/marketplace.json": claude_catalog,
        f"plugins/{NAME}/plugin.json": portable,
        f"plugins/{NAME}/.codex-plugin/plugin.json": codex,
        f"plugins/{NAME}/.cursor-plugin/plugin.json": cursor,
        f"plugins/{NAME}/gemini-extension.json": gemini,
        ".agents/plugins/marketplace.json": update_catalog(".agents/plugins/marketplace.json", codex_catalog),
        ".cursor-plugin/marketplace.json": update_catalog(".cursor-plugin/marketplace.json", catalog),
        ".github/plugin/marketplace.json": update_catalog(".github/plugin/marketplace.json", catalog),
    }


def sync(check):
    stale = []
    for relative, value in manifests().items():
        path = ROOT / relative
        content = encoded(value)
        if path.is_file() and path.read_text(encoding="utf-8") == content:
            continue
        if check:
            stale.append(relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            write(path, content)
    if stale:
        raise ValueError("Stale host metadata: " + ", ".join(stale) + ". Run --sync-manifests.")


def archive(folder, destination):
    # Fixed timestamps and order make identical source packages reproducible.
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as output:
        for path in sorted(folder.rglob("*")):
            if not path.is_file():
                continue
            if path.is_symlink():
                raise ValueError(f"Unmaterialized symlink in release: {path}")
            member = zipfile.ZipInfo((Path(folder.name) / path.relative_to(folder)).as_posix(), (1980, 1, 1, 0, 0, 0))
            member.compress_type = zipfile.ZIP_DEFLATED
            member.external_attr = (0o100644 << 16)
            output.writestr(member, path.read_bytes())


def copy_skill(destination):
    source = ROOT / "skills" / META["skill"]
    # Validate before copytree dereferences links: the archive guard cannot detect
    # an outside file once it has become a regular file in the staging directory.
    if source.is_symlink() or any(path.is_symlink() for path in source.rglob("*")):
        raise ValueError(f"Canonical {META['skill']} skill must not contain symlinks; release only real scoped files.")
    shutil.copytree(source, destination,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store", ".env", ".git"))
    # Maintainer links to repository docs/tests are navigation, not runtime skill
    # dependencies. Resolve those links to the published repository in releases.
    for original in source.rglob("*.md"):
        def target(match):
            value = match.group(1)
            if value.startswith(("https://", "http://", "mailto:", "#")):
                return match.group(0)
            file_part, marker, anchor = value.partition("#")
            resolved = (original.parent / file_part).resolve()
            if resolved.is_relative_to(source.resolve()) or not resolved.is_relative_to(ROOT.resolve()):
                return match.group(0)
            kind = "tree" if resolved.is_dir() else "blob"
            url = f"https://github.com/getditto/agent-skills/{kind}/main/{resolved.relative_to(ROOT).as_posix()}"
            return "](" + url + (marker + anchor if marker else "") + ")"
        write(destination / original.relative_to(source), re.sub(r"\]\(([^)]+)\)", target, original.read_text(encoding="utf-8")))


def build(destination):
    sync(check=True)
    if destination.exists():
        raise ValueError(f"Output already exists: {destination}. Choose a new directory.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".ditto-package-", dir=destination.parent))
    try:
        marketplace = staging / f"{NAME}-marketplace"
        package = marketplace / "plugins" / NAME
        package.mkdir(parents=True)
        for relative, value in manifests().items():
            if relative.endswith("marketplace.json"):
                value = {**value, "plugins": [entry for entry in value["plugins"] if entry["name"] == NAME]}
            target = marketplace / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            write(target, encoded(value))
        (marketplace / ".claude-plugin").mkdir(exist_ok=True)
        legacy = json.loads((PLUGIN / ".claude-plugin/plugin.json").read_text(encoding="utf-8"))
        write(marketplace / ".claude-plugin/marketplace.json", encoded({
            "name": "ditto-plugins", "owner": legacy["author"], "plugins": [{
                "name": NAME, "source": f"./plugins/{NAME}", "description": legacy["description"],
            }]}))
        (package / ".claude-plugin").mkdir()
        write(package / ".claude-plugin/plugin.json", encoded(legacy))
        # Materialize only the explicitly shipped canonical skill. Never copy the
        # repository root, environment, test credentials, or another plugin's skills.
        copy_skill(package / "skills" / META["skill"])
        if (ROOT / "LICENSE").is_file():
            shutil.copy2(ROOT / "LICENSE", package / "LICENSE")
        shutil.copy2(ROOT / META["install_doc"], marketplace / "INSTALL.md")
        for extra in META["extra_docs"]:
            shutil.copy2(ROOT / extra, marketplace / Path(extra).name)
        hashes = {path.relative_to(package).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted(package.rglob("*")) if path.is_file()}
        write(package / "PACKAGE-MANIFEST.json", encoded({"plugin": NAME, "version": legacy["version"], "sha256": hashes}))

        # Antigravity has its own small manifest schema; do not rename an Agent
        # Plugins manifest and assume its additional fields will be accepted.
        antigravity = staging / f"{NAME}-antigravity"
        antigravity.mkdir()
        write(antigravity / "plugin.json", encoded({"name": NAME, "description": legacy["description"]}))
        shutil.copytree(package / "skills", antigravity / "skills")
        if (ROOT / "LICENSE").is_file():
            shutil.copy2(ROOT / "LICENSE", antigravity / "LICENSE")
        # Standalone extension, so Gemini does not discover unrelated root skills.
        gemini = staging / f"{NAME}-gemini"
        gemini.mkdir()
        shutil.copy2(package / "gemini-extension.json", gemini / "gemini-extension.json")
        shutil.copytree(package / "skills", gemini / "skills")
        if (ROOT / "LICENSE").is_file():
            shutil.copy2(ROOT / "LICENSE", gemini / "LICENSE")
        # Claude's per-skill upload fallback gets a skill folder at the archive root.
        uploads = staging / "skill-upload"
        uploads.mkdir()
        shutil.copytree(package / "skills" / META["skill"], uploads / META["skill"])
        archive(marketplace, staging / f"{NAME}-marketplace.zip")
        archive(package, staging / f"{NAME}-plugin.zip")
        archive(antigravity, staging / f"{NAME}-antigravity.zip")
        archive(gemini, staging / f"{NAME}-gemini.zip")
        archive(uploads / META["skill"], staging / f"{META['skill']}.zip")
        write(staging / "SHA256SUMS", "".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in sorted(staging.glob("*.zip"))))
        staging.rename(destination)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print(f"Built {NAME}-only packages in {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    parser.add_argument("--plugin", choices=sorted(PLUGINS), default="ditto-swift", help="which plugin wrapper to operate on")
    mode.add_argument("--check", action="store_true", help="check committed metadata matches the plugin's canonical Claude manifest")
    mode.add_argument("--sync-manifests", action="store_true", help="regenerate host metadata")
    parser.add_argument("--output", type=Path, help="package output directory (default: dist/<language>)")
    args = parser.parse_args()
    configure(args.plugin)
    if args.output is None:
        args.output = ROOT / "dist" / NAME.removeprefix("ditto-")
    try:
        if args.check or args.sync_manifests:
            sync(check=args.check)
            print(f"{META['display_name']} host metadata is current")
        else:
            build(args.output.expanduser().absolute())
    except (OSError, ValueError) as error:
        parser.exit(1, f"Packaging failed: {error}\n")


if __name__ == "__main__":
    main()
