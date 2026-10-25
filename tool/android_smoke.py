"""Exercise the installed preview through Android UI; no fake app state."""
import hashlib
import json
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET

OUT = pathlib.Path('smoke-evidence')
OUT.mkdir(exist_ok=True)
PACKAGE = 'app.flowshare.flowshare'


def adb(*args, check=True):
    return subprocess.run(['adb', *args], check=check, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.decode(errors='replace')


def snapshot(name):
    with (OUT / f'{name}.png').open('wb') as image:
        subprocess.run(['adb', 'exec-out', 'screencap', '-p'], check=True, stdout=image)


def tree():
    adb('shell', 'rm', '-f', '/sdcard/flowshare-ui.xml')
    adb('shell', 'uiautomator', 'dump', '/sdcard/flowshare-ui.xml')
    xml = adb('shell', 'cat', '/sdcard/flowshare-ui.xml')
    (OUT / 'last-ui.xml').write_text(xml)
    return ET.fromstring(xml)


def label(node):
    return '\n'.join([node.get('text', ''), node.get('content-desc', '')]).strip()


def wait_for(text, timeout=70, scroll=None):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            root = tree()
            for node in root.iter('node'):
                if text == label(node) or text in label(node).splitlines():
                    return node
            all_text = ' '.join(label(n) for n in root.iter('node'))
            if 'could not open secure storage' in all_text:
                raise RuntimeError('App initialization failed: ' + all_text)
            if scroll:
                width, height = map(int, re.findall(r'(\d+)x(\d+)', adb('shell', 'wm', 'size'))[-1])
                start, end = (0.72, 0.36) if scroll == 'down' else (0.36, 0.72)
                adb('shell', 'input', 'swipe', str(width//2), str(int(height*start)), str(width//2), str(int(height*end)), '400')
        except (ET.ParseError, subprocess.CalledProcessError):
            pass
        time.sleep(1)
    snapshot('failure')
    raise RuntimeError(f'Expected UI text did not appear: {text}')


def tap(text, scroll=None):
    node = wait_for(text, scroll=scroll)
    bounds = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
    if len(bounds) != 4:
        raise RuntimeError(f'Cannot tap UI node: {text}')
    x1, y1, x2, y2 = bounds
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
    time.sleep(0.5)


apk = next(pathlib.Path('apk').glob('*x86_64*.apk'))
expected = next(line.split()[0] for line in pathlib.Path('apk/SHA256SUMS.txt').read_text().splitlines() if line.endswith(apk.name))
actual = hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest()
assert actual == expected, 'APK does not match build checksum'
checks = []
try:
    adb('install', '-r', str(apk))
    adb('shell', 'pm', 'clear', PACKAGE)
    adb('logcat', '-c')
    adb('shell', 'settings', 'put', 'system', 'screen_off_timeout', '600000')
    adb('shell', 'am', 'start', '-W', '-n', PACKAGE+'/.MainActivity')
    wait_for('Next')
    snapshot('01-onboarding')
    tap('Next'); tap('Next'); tap('Get started')
    wait_for('Your files. Your devices.')
    snapshot('02-home-light')
    checks.append('Native installation, secure-storage/database initialization, onboarding and home')
    tap('History')
    wait_for('Your transfers will appear here')
    snapshot('03-history')
    checks.append('History empty state')
    tap('Settings')
    # Android's legacy XML dumper omits Flutter text-field hint labels.
    # Check the actual editable value and surrounding Settings sections.
    wait_for('My device')
    wait_for('FlowShare android')
    wait_for('Appearance')
    snapshot('04-settings')
    checks.append('Settings navigation')
    tap('Home')
    tap('Receive files')
    tap('Start receiving')
    wait_for('Stop receiving')
    wait_for('Copy pairing link', scroll='down')
    snapshot('05-receive-qr')
    checks.append('Native receive listener and QR invitation')
    tap('Stop receiving', scroll='up')
    wait_for('Start receiving')
    checks.append('Listener stop')
    adb('shell', 'am', 'force-stop', PACKAGE)
    adb('shell', 'am', 'start', '-W', '-n', PACKAGE+'/.MainActivity')
    wait_for('Your files. Your devices.')
    checks.append('Restart retains onboarding and initializes persisted identity')
    (OUT/'result.json').write_text(json.dumps({'status':'passed','checks':checks,'apk_sha256':actual,'scope':'Android emulator only; not physical cross-device transfer'},indent=2))
    print(json.dumps({'status':'passed','checks':checks}))
finally:
    try:
        snapshot('last-screen')
    except subprocess.CalledProcessError:
        pass
    (OUT/'logcat.txt').write_text(adb('logcat','-d','-v','time',check=False))

