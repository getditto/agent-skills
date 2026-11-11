#!/usr/bin/env python3
"""Package the scoped JavaScript skill family, including its native configuration dependency."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SKILLS = ('js-sdk', 'js-node', 'js-web', 'js-react-native', 'js-expo', 'native-app-config')
NAME = 'ditto-js'
PLUGIN = ROOT / 'plugins' / NAME


def encoded(value):
    return json.dumps(value, indent=2, ensure_ascii=False) + '\n'


def manifests():
    identity = json.loads((PLUGIN / '.claude-plugin/plugin.json').read_text())
    interface = {'displayName': 'Ditto JavaScript', 'shortDescription': 'Build Ditto apps for Node, web, React Native and Expo.',
                 'developerName': 'Ditto', 'category': 'Developer Tools', 'capabilities': ['Read', 'Write'],
                 'defaultPrompt': ['Build an Expo task app with Ditto.', 'Integrate Ditto into this React Native app.']}
    source = './plugins/ditto-js'
    result = {
        'plugins/ditto-js/plugin.json': {'$schema': 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json', **identity},
        'plugins/ditto-js/.codex-plugin/plugin.json': {**identity, 'skills': './skills/', 'interface': interface},
        'plugins/ditto-js/.cursor-plugin/plugin.json': {**identity, 'skills': './skills/'},
        'plugins/ditto-js/gemini-extension.json': {key: identity[key] for key in ('name', 'version', 'description')},
    }
    for relative in ('.agents/plugins/marketplace.json', '.cursor-plugin/marketplace.json', '.github/plugin/marketplace.json'):
        catalog = json.loads((ROOT / relative).read_text())
        entry = {'name': NAME, 'source': source, 'description': identity['description']}
        if relative.startswith('.agents'):
            entry = {'name': NAME, 'source': {'source': 'local', 'path': source},
                     'policy': {'installation': 'AVAILABLE', 'authentication': 'ON_INSTALL'}, 'category': 'Developer Tools'}
        entries = catalog['plugins']
        position = next((i for i, existing in enumerate(entries) if existing['name'] == NAME), None)
        if position is None:
            entries.insert(0, entry)
        else:
            entries[position] = entry
        result[relative] = catalog
    return result


def sync(check=False):
    for relative, data in manifests().items():
        path = ROOT / relative
        expected = encoded(data)
        if path.exists() and path.read_text() == expected:
            continue
        if check:
            raise ValueError(f'Stale metadata: {relative}; run --sync-manifests')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected)


def copy_skills(destination):
    wrappers = PLUGIN / 'skills'
    if {p.name for p in wrappers.iterdir()} != set(SKILLS):
        raise ValueError('JavaScript plugin scope differs from declared skill list')
    for name in SKILLS:
        source = ROOT / 'skills' / name
        if not (wrappers / name).is_symlink() or (wrappers / name).resolve() != source.resolve():
            raise ValueError(f'Invalid scoped wrapper for {name}')
        if source.is_symlink() or any(p.is_symlink() for p in source.rglob('*')):
            raise ValueError(f'Canonical skill contains a symlink: {name}')
        target = destination / name
        shutil.copytree(source, target, ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '.DS_Store', '.env', '.git'))
        for original in source.rglob('*.md'):
            def rewrite(match):
                value = match[1]
                if value.startswith(('http:', 'https:', 'mailto:', '#')):
                    return match[0]
                file, marker, anchor = value.partition('#')
                resolved = (original.parent / file).resolve()
                # Keep links to sibling dependencies local: all six skills ship together.
                if any(resolved.is_relative_to(ROOT / 'skills' / skill) for skill in SKILLS):
                    return match[0]
                if not resolved.is_relative_to(ROOT):
                    raise ValueError(f'Link escapes repository: {original}: {value}')
                kind = 'tree' if resolved.is_dir() else 'blob'
                return f'](https://github.com/getditto/agent-skills/{kind}/main/{resolved.relative_to(ROOT).as_posix()}{marker}{anchor})'
            (target / original.relative_to(source)).write_text(re.sub(r'\]\(([^)]+)\)', rewrite, original.read_text()))


def archive(folder, destination):
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED) as output:
        for path in sorted(folder.rglob('*')):
            if not path.is_file():
                continue
            if path.is_symlink():
                raise ValueError(f'Unmaterialized symlink: {path}')
            member = zipfile.ZipInfo((Path(folder.name) / path.relative_to(folder)).as_posix(), (1980, 1, 1, 0, 0, 0))
            member.compress_type = zipfile.ZIP_DEFLATED
            member.external_attr = 0o100644 << 16
            output.writestr(member, path.read_bytes())


def build(destination):
    sync(check=True)
    if destination.exists():
        raise ValueError(f'Output exists: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        stage = Path(temporary)
        package = stage / NAME
        package.mkdir()
        for file in ('plugin.json', '.claude-plugin/plugin.json', '.codex-plugin/plugin.json', '.cursor-plugin/plugin.json', 'gemini-extension.json'):
            target = package / file
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(PLUGIN / file, target)
        copy_skills(package / 'skills')
        if (ROOT / 'LICENSE').is_file():
            shutil.copy2(ROOT / 'LICENSE', package / 'LICENSE')
        (package / 'INSTALL.md').write_text((ROOT / 'docs/install-js.md').read_text().replace(
            '](../tests/js-sdk/README.md)',
            '](https://github.com/getditto/agent-skills/blob/main/tests/js-sdk/README.md)'))
        hashes = {p.relative_to(package).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(package.rglob('*')) if p.is_file()}
        (package / 'PACKAGE-MANIFEST.json').write_text(encoded({'plugin': NAME, 'sha256': hashes}))
        archive(package, stage / 'ditto-js-plugin.zip')
        # A portable skills bundle preserves sibling links and generator dependencies.
        portable = stage / 'ditto-js-skills'
        shutil.copytree(package / 'skills', portable / 'skills')
        archive(portable, stage / 'ditto-js-skills.zip')
        (stage / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in sorted(stage.glob('*.zip'))))
        shutil.copytree(stage, destination)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--sync-manifests', action='store_true')
    mode.add_argument('--check', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/js')
    args = parser.parse_args()
    try:
        if args.sync_manifests or args.check:
            sync(check=args.check)
        else:
            build(args.output.absolute())
    except (ValueError, OSError) as error:
        parser.exit(1, f'{error}\n')
