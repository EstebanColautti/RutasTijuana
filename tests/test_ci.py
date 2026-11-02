import importlib.util
from pathlib import Path
import unittest
import tempfile
import plistlib


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


select = load('ci_select').select
successful = load('ci_summary').successful


class CISelectionTests(unittest.TestCase):
    def test_selection(self):
        for files, web, native in [(['README.md'], False, False), (['docs/DESARROLLO.md'], False, False), (['admin/src/main.tsx'], True, False), (['preview/app.js'], True, False), (['RutasTijuana/WalkingNavigation.swift'], False, True), (['NavigationWidget/Info.plist'], False, True), (['Config/Debug.xcconfig'], False, True), (['tests/main.swift'], True, True), (['scripts/test-logic.sh'], True, True), (['.github/workflows/build.yml'], True, True), (['pnpm-lock.yaml'], True, True), (['unknown'], True, True), (None, True, True)]:
            with self.subTest(files=files):
                result = select(files)
                self.assertEqual((result['web'], result['native']), (web, native))

    def test_modes(self):
        self.assertEqual(select([], 'push')['native'], True)
        self.assertEqual(select([], 'workflow_dispatch', 'native')['web'], False)
        self.assertEqual(select([], 'workflow_dispatch')['web'], True)

    def test_summary(self):
        def results(web='skipped', native='success', ui='success'):
            return {'changes': {'result': 'success', 'outputs': {'web': 'false', 'native': 'true'}}, 'web': {'result': web}, 'native': {'result': native}, 'ui': {'result': ui}}
        self.assertTrue(successful(results()))
        for result in ('failure', 'cancelled', 'timed_out', 'skipped'):
            self.assertFalse(successful(results(ui=result)))
        self.assertFalse(successful({'changes': {'result': 'failure'}}))
        self.assertFalse(successful({'changes': {'result': 'success'}}))
        value = results(native='skipped', ui='skipped')
        value['changes']['outputs']['native'] = 'false'
        self.assertTrue(successful(value))


class BundleTests(unittest.TestCase):
    def test_extension_versions_and_capabilities(self):
        validate = load('check_app_bundle').validate
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'App.app'
            extension = app / 'PlugIns' / 'Navigation.appex'
            extension.mkdir(parents=True)
            info = {'CFBundleIdentifier': 'com.estebancolautti.rutastijuana', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0', 'NSSupportsLiveActivities': True, 'UIBackgroundModes': ['location'], 'NSLocationWhenInUseUsageDescription': 'Ejemplo', 'NSLocationTemporaryUsageDescriptionDictionary': {'WalkingNavigation': 'Ejemplo'}}
            widget = {'CFBundleIdentifier': info['CFBundleIdentifier'] + '.navigation', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0', 'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}}
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            (extension / 'Info.plist').write_bytes(plistlib.dumps(widget))
            validate(app)
            for key in ('CFBundleVersion', 'CFBundleShortVersionString', 'NSExtension'):
                broken = dict(widget)
                del broken[key]
                (extension / 'Info.plist').write_bytes(plistlib.dumps(broken))
                with self.assertRaises(AssertionError):
                    validate(app)
