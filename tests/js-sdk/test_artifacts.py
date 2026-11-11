"""Structural and generated-native checks; these do not claim hardware execution."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('js_packager', ROOT / 'scripts/package-js-plugin.py')
PACKAGER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGER)
ANDROID = '{http://schemas.android.com/apk/res/android}'


class ArtifactTests(unittest.TestCase):
    def test_config_fragments(self):
        assets = ROOT / 'skills/native-app-config/assets'
        info = plistlib.loads((assets / 'Info.plist').read_bytes())
        self.assertIn('_http-alt._tcp.', info['NSBonjourServices'])
        self.assertTrue(info['NSBluetoothAlwaysUsageDescription'])
        entitlements = plistlib.loads((assets / 'App.entitlements').read_bytes())
        self.assertEqual(entitlements['com.apple.developer.default-data-protection'], 'NSFileProtectionCompleteUntilFirstUserAuthentication')
        permissions = {p.attrib[ANDROID+'name']: p.attrib for p in ET.parse(assets / 'AndroidManifest.xml').getroot()}
        self.assertEqual(permissions['android.permission.ACCESS_FINE_LOCATION'][ANDROID+'maxSdkVersion'], '32')
        self.assertEqual(permissions['android.permission.BLUETOOTH'][ANDROID+'maxSdkVersion'], '30')
        self.assertEqual(permissions['android.permission.BLUETOOTH_SCAN'][ANDROID+'usesPermissionFlags'], 'neverForLocation')

    def test_release_is_reproducible_scoped_and_generator_works_after_install(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            PACKAGER.build(folder / 'one')
            PACKAGER.build(folder / 'two')
            for archive in (folder / 'one').glob('*.zip'):
                self.assertEqual(archive.read_bytes(), (folder / 'two' / archive.name).read_bytes())
                with zipfile.ZipFile(archive) as zipped:
                    skills = {Path(name).parent.name for name in zipped.namelist() if name.endswith('/SKILL.md')}
                    self.assertEqual(skills, set(PACKAGER.SKILLS))
                    self.assertFalse(any('/tests/' in name or '/node_modules/' in name or '/.env' in name for name in zipped.namelist()))
            installed = folder / 'one/ditto-js/skills'
            subprocess.run([sys.executable, str(installed / 'js-expo/scripts/create-app.py'), str(folder / 'app')], check=True, capture_output=True)
            self.assertEqual((folder / 'app/src/runtime.ts').read_bytes(), (ROOT / 'skills/js-sdk/assets/runtime.ts').read_bytes())
            existing = subprocess.run([sys.executable, str(installed / 'js-expo/scripts/create-app.py'), str(folder / 'app')], capture_output=True)
            self.assertNotEqual(existing.returncode, 0)
            # Required runtime references remain local after extracting only the plugin.
            for name in ('js-sdk', 'js-react-native', 'native-app-config'):
                self.assertTrue((installed / name / 'SKILL.md').is_file())


def verify_native(mobile):
    """Called explicitly after prebuild; missing output is a failure, never a skip."""
    info = plistlib.loads(next((mobile / 'ios').glob('*/Info.plist')).read_bytes())
    for key in ('NSBluetoothAlwaysUsageDescription', 'NSLocalNetworkUsageDescription'):
        assert info[key], key
    assert info['NSBonjourServices'].count('_http-alt._tcp.') == 1
    for mode in ('bluetooth-central', 'bluetooth-peripheral'):
        assert info['UIBackgroundModes'].count(mode) == 1
    manifest = ET.parse(mobile / 'android/app/src/main/AndroidManifest.xml').getroot()
    names = [p.attrib[ANDROID+'name'] for p in manifest.findall('uses-permission')]
    assert len(names) == len(set(names)), 'duplicate permissions'
    for permission in ('BLUETOOTH_SCAN', 'BLUETOOTH_CONNECT', 'BLUETOOTH_ADVERTISE', 'NEARBY_WIFI_DEVICES', 'ACCESS_FINE_LOCATION', 'INTERNET'):
        assert 'android.permission.' + permission in names, permission
    build = (mobile / 'android/build.gradle').read_text()
    assert build.count("classpath('org.jetbrains.kotlin:kotlin-gradle-plugin:2.3.0')") == 1
    properties = (mobile / 'android/gradle.properties').read_text()
    assert properties.count('android.kotlinVersion=2.3.0') == 1
    scenes = info['UIApplicationSceneManifest']['UISceneConfigurations']['UIWindowSceneSessionRoleApplication']
    assert len(scenes) == 1
    assert 'SceneDelegate' in scenes[0]['UISceneDelegateClassName']
    print('Generated iOS and Android configuration verified')


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == '--native':
        verify_native(HERE / 'mobile')
    else:
        unittest.main()
