import plistlib
from pathlib import Path
import sys


def validate(app):
    app = Path(app)
    with (app / 'Info.plist').open('rb') as file:
        info = plistlib.load(file)
    identifier = info['CFBundleIdentifier']
    assert identifier == 'com.estebancolautti.rutastijuana'
    assert info.get('NSSupportsLiveActivities') is True
    assert 'location' in info.get('UIBackgroundModes', [])
    assert info.get('NSLocationWhenInUseUsageDescription')
    assert info.get('NSLocationTemporaryUsageDescriptionDictionary', {}).get('WalkingNavigation')
    extensions = list((app / 'PlugIns').glob('*.appex'))
    assert len(extensions) == 1
    with (extensions[0] / 'Info.plist').open('rb') as file:
        extension = plistlib.load(file)
    assert extension['CFBundleIdentifier'] == identifier + '.navigation'
    for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
        assert info.get(key) and extension.get(key) == info[key], key
    assert extension.get('NSExtension', {}).get('NSExtensionPointIdentifier') == 'com.apple.widgetkit-extension'
    print('Paquetes de iPhone correctos.')


if __name__ == '__main__':
    validate(sys.argv[1])
