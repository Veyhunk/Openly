#!/usr/bin/env python3
"""Create the manager and on-demand Launch Services receiver bundles."""
import json
import plistlib
import shutil
import subprocess
from pathlib import Path
import sys
import re
import os
import uuid

def atomic_copy(source, target):
    temporary = target.with_name('.' + target.name + '-' + str(uuid.uuid4()))
    shutil.copy2(source, temporary)
    os.replace(temporary, target)

root = Path(__file__).resolve().parent.parent
configuration = sys.argv[1] if len(sys.argv) > 1 else 'release'
if configuration not in ('debug', 'release'):
    raise SystemExit('Configuration must be debug or release')
subprocess.run(['swift', 'build', '-c', configuration], cwd=root, check=True)
bin_dir = Path(subprocess.check_output(['swift', 'build', '-c', configuration, '--show-bin-path'], cwd=root, text=True).strip())
app = root / '.build' / 'Openly.app'
receiver = app / 'Contents' / 'Helpers' / 'Openly Receiver.app'
version_source = (root / 'Sources/App/Version.swift').read_text()
version = re.search(r'static let current = "([^"]+)"', version_source).group(1)
build = re.search(r'static let build = "([^"]+)"', version_source).group(1)
description = json.loads((root / 'Sources/Resources/extension_descriptions.json').read_text())
extensions = sorted(set(e for values in description['categories'].values() for e in values))
for bundle, identifier, agent in [(app, 'com.openly.app', False), (receiver, 'com.openly.receiver', True)]:
    contents = bundle / 'Contents'
    (contents / 'MacOS').mkdir(parents=True, exist_ok=True)
    (contents / 'Resources').mkdir(parents=True, exist_ok=True)
    atomic_copy(bin_dir / 'Openly', contents / 'MacOS/Openly')
    for resource in (root / 'Sources/Resources').iterdir():
        if resource.is_file(): shutil.copy2(resource, contents / 'Resources' / resource.name)
    info = {
        'CFBundleName': 'Openly', 'CFBundleDisplayName': 'Openly',
        'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'Openly',
        'CFBundlePackageType': 'APPL', 'CFBundleVersion': build, 'CFBundleShortVersionString': version,
        'CFBundleIconFile': 'AppIcon', 'LSMinimumSystemVersion': '14.0',
        'NSHighResolutionCapable': True, 'NSAppleEventsUsageDescription': 'Openly 根据你的选择将文件或链接打开到指定应用窗口。'
    }
    if agent:
        info.update({
            'LSUIElement': True, 'OpenlyReceiver': True,
            'CFBundleURLTypes': [{'CFBundleURLName': 'Web links', 'CFBundleURLSchemes': ['http', 'https'], 'CFBundleTypeRole': 'Viewer'}],
            'CFBundleDocumentTypes': [{'CFBundleTypeName': 'Files', 'CFBundleTypeRole': 'Viewer', 'LSHandlerRank': 'None', 'LSItemContentTypes': ['public.data', 'public.content'], 'CFBundleTypeExtensions': extensions}]
        })
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
atomic_copy(bin_dir / 'OpenlyBridge', app / 'Contents/MacOS/OpenlyBridge')
shutil.copytree(root / 'BrowserExtension', app / 'Contents/Resources/BrowserExtension', dirs_exist_ok=True)
for binary in [app / 'Contents/MacOS/OpenlyBridge', receiver, app]:
    subprocess.run(['codesign', '--force', '--sign', '-', str(binary)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(app)
