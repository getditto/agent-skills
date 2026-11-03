#!/usr/bin/env python3
"""Generate a self-contained SwiftUI/Xcode starter without changing an existing app."""

import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

KNOWN_VERSION = "5.2.0"  # Knowledge/test baseline, never a default dependency pin.
PACKAGE_URL = "https://github.com/getditto/DittoSwiftPackage"
SKILL = Path(__file__).resolve().parents[1]


def release_version(value):
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", value):
        raise ValueError("SDK version must be a stable major.minor.patch release")
    return tuple(map(int, value.split(".")))


def latest_version():
    """Resolve stable SwiftPM tags; fail rather than silently pinning stale knowledge."""
    result = subprocess.run(
        ["git", "ls-remote", "--tags", "--refs", PACKAGE_URL],
        check=True, capture_output=True, text=True, timeout=60,
    )
    versions = re.findall(r"refs/tags/([0-9]+\.[0-9]+\.[0-9]+)$", result.stdout, re.MULTILINE)
    if not versions:
        raise ValueError("No stable SwiftPM release tags found; check the package repository")
    return max(versions, key=release_version)


def write(path, content):
    with path.open("w", encoding="utf-8", newline="\n") as output:
        output.write(content)


def openstep(value, indent=0):
    """Serialize the small OpenStep plist subset used by an Xcode project."""
    pad = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join(
            f"{pad}\t{json.dumps(str(key))} = {openstep(item, indent + 1)};\n"
            for key, item in value.items()
        ) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{pad}\t{openstep(item, indent + 1)},\n" for item in value) + pad + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(str(value), ensure_ascii=True)


def project(name, bundle_id, version):
    objects = {}

    def add(kind, **fields):
        key = f"{len(objects) + 1:024X}"
        objects[key] = {"isa": kind, **fields}
        return key

    swift = add("PBXFileReference", lastKnownFileType="sourcecode.swift", path="StarterApp.swift", sourceTree="<group>")
    config = add("PBXFileReference", lastKnownFileType="text.plist.xml", path="LocalConfig.plist", sourceTree="<group>")
    info = add("PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>")
    entitlements = add("PBXFileReference", lastKnownFileType="text.plist.entitlements", path="Mac.entitlements", sourceTree="<group>")
    product = add("PBXFileReference", explicitFileType="wrapper.application", path=f"{name}.app", sourceTree="BUILT_PRODUCTS_DIR")
    app_group = add("PBXGroup", children=[swift, config, info, entitlements], path="App", sourceTree="<group>")
    products = add("PBXGroup", children=[product], name="Products", sourceTree="<group>")
    group = add("PBXGroup", children=[app_group, products], sourceTree="<group>")
    package = add("XCRemoteSwiftPackageReference", repositoryURL="https://github.com/getditto/DittoSwiftPackage",
                  requirement={"kind": "exactVersion", "version": version})
    dependency = add("XCSwiftPackageProductDependency", package=package, productName="DittoSwift")
    source_build = add("PBXBuildFile", fileRef=swift)
    config_build = add("PBXBuildFile", fileRef=config)
    framework_build = add("PBXBuildFile", productRef=dependency)
    sources = add("PBXSourcesBuildPhase", buildActionMask=2147483647, files=[source_build], runOnlyForDeploymentPostprocessing=0)
    resources = add("PBXResourcesBuildPhase", buildActionMask=2147483647, files=[config_build], runOnlyForDeploymentPostprocessing=0)
    frameworks = add("PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[framework_build], runOnlyForDeploymentPostprocessing=0)
    # Xcode's SPM integration populates the embedding work for the binary product.
    embed = add("PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=10,
                files=[], name="Embed Frameworks", runOnlyForDeploymentPostprocessing=0)

    def configurations(settings):
        ids = []
        for configuration in ("Debug", "Release"):
            flags = "$(inherited)" + (" DEBUG" if configuration == "Debug" else "")
            if version.startswith("4."):
                flags += " DITTO_V4"
            ids.append(add("XCBuildConfiguration", name=configuration, buildSettings={
                **settings, "SWIFT_ACTIVE_COMPILATION_CONDITIONS": flags,
                "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O",
                "ONLY_ACTIVE_ARCH": "YES" if configuration == "Debug" else "NO",
            }))
        return add("XCConfigurationList", buildConfigurations=ids, defaultConfigurationIsVisible=0,
                   defaultConfigurationName="Release")

    target_config = configurations({
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
        "INFOPLIST_FILE": "App/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "SWIFT_VERSION": "6.0", "SDKROOT": "auto",
        **({"ARCHS": "arm64"} if release_version(version) >= (5, 1, 0) else {}),
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
        "SUPPORTS_MACCATALYST": "YES", "TARGETED_DEVICE_FAMILY": "1,2",
        "IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGNING_ALLOWED": "YES", "CODE_SIGNING_REQUIRED": "YES",
        "COPY_PHASE_STRIP": "NO",
        "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "App/Mac.entitlements",
        "ENABLE_HARDENED_RUNTIME": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    })
    target = add("PBXNativeTarget", name=name, productName=name, productReference=product,
                 productType="com.apple.product-type.application", buildConfigurationList=target_config,
                 buildPhases=[sources, frameworks, resources, embed], buildRules=[], dependencies=[],
                 packageProductDependencies=[dependency])
    root = add("PBXProject", attributes={"LastUpgradeCheck": "1600"},
               buildConfigurationList=configurations({"CLANG_ENABLE_MODULES": "YES"}),
               compatibilityVersion="Xcode 14.0", developmentRegion="en", knownRegions=["en", "Base"],
               mainGroup=group, productRefGroup=products, projectDirPath="", projectRoot="",
               packageReferences=[package], targets=[target])
    return {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": root}, target


def scheme(name, target):
    root = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    action = ET.SubElement(root, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(action, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", **{f"buildFor{key}": "YES" for key in ("Testing", "Running", "Profiling", "Archiving", "Analyzing")})
    attributes = dict(BuildableIdentifier="primary", BlueprintIdentifier=target,
                      BuildableName=f"{name}.app", BlueprintName=name, ReferencedContainer=f"container:{name}.xcodeproj")
    ET.SubElement(entry, "BuildableReference", **attributes)
    launch = ET.SubElement(root, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                           selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO",
                           ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="YES")
    runnable = ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0")
    ET.SubElement(runnable, "BuildableReference", **attributes)
    ET.SubElement(root, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(root, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(root)
    return ET.tostring(root, encoding="unicode") + "\n"


def generate(destination, name, bundle_id, version):
    if destination.exists():
        raise ValueError(f"Destination already exists: {destination}. Choose a new directory.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".ditto-starter-", dir=destination.parent))
    try:
        app = staging / "App"
        app.mkdir()
        shutil.copy2(SKILL / "assets/swiftui-starter/StarterApp.swift", app / "StarterApp.swift")
        info = {
            "CFBundleDevelopmentRegion": "en", "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
            "NSBluetoothAlwaysUsageDescription": "Sync notes with nearby devices using Bluetooth.",
            "NSBluetoothPeripheralUsageDescription": "Sync notes with nearby devices using Bluetooth.",
            "NSLocalNetworkUsageDescription": "Discover and sync notes with nearby devices on the local network.",
            "NSBonjourServices": ["_http-alt._tcp."], "UILaunchScreen": {},
        }
        for filename, data in {
            "Info.plist": info,
            "LocalConfig.plist": {"DatabaseID": "", "OfflineLicense": ""},
            "LocalConfig.example.plist": {"DatabaseID": "YOUR_DATABASE_UUID", "OfflineLicense": "YOUR_OFFLINE_LICENSE"},
            "Mac.entitlements": {"com.apple.security.app-sandbox": True,
                                 "com.apple.security.network.client": True, "com.apple.security.network.server": True,
                                 "com.apple.security.device.bluetooth": True},
        }.items():
            (app / filename).write_bytes(plistlib.dumps(data))
        xcode = staging / f"{name}.xcodeproj"
        shared = xcode / "xcshareddata/xcschemes"
        shared.mkdir(parents=True)
        data, target = project(name, bundle_id, version)
        write(xcode / "project.pbxproj", "// !$*UTF8*$!\n" + openstep(data) + "\n")
        write(shared / f"{name}.xcscheme", scheme(name, target))
        write(staging / ".gitignore", "App/LocalConfig.plist\nDerivedData/\n*.xcuserstate\nxcuserdata/\n.DS_Store\n")
        readme = (SKILL / "assets/swiftui-starter/README.md").read_text(encoding="utf-8")
        write(staging / "README.md", readme.replace("@APP_NAME@", name).replace("@SDK_VERSION@", version))
        # An atomic rename never merges with or overwrites an existing project.
        staging.rename(destination)
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--name", default="DittoNotes")
    parser.add_argument("--bundle-id", default="com.example.ditto.notes")
    parser.add_argument("--sdk-version", default="latest",
                        help="latest stable SwiftPM tag (default), or an explicit stable version")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,63}", args.name):
        parser.error("--name must start with a letter and contain only letters, digits or underscores (max 64)")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        parser.error("--bundle-id must be a reverse-DNS identifier")
    try:
        version = latest_version() if args.sdk_version == "latest" else args.sdk_version
        release_version(version)
        destination = args.destination.expanduser().absolute()
        generate(destination, args.name, args.bundle_id, version)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Cannot generate project: {error}\n")
    print(f"Created {destination / (args.name + '.xcodeproj')} (Ditto {version})")
    if release_version(version) > release_version(KNOWN_VERSION):
        print(f"Skill knowledge ends at {KNOWN_VERSION}; review {version}'s release notes and validate the generated app.")
    print(f"Configure {destination / 'App/LocalConfig.plist'}, then follow {destination / 'README.md'}")


if __name__ == "__main__":
    main()
