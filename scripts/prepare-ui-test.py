#!/usr/bin/env python3
"""Create a separate receiver identity for UI tests without interrupting active requests."""
from pathlib import Path
import plistlib, shutil, subprocess
root = Path(__file__).resolve().parent.parent
source = root / '.build/Openly.app/Contents/Helpers/Openly Receiver.app'
target = root / '.build/checks/Openly UI Test.app'
shutil.copytree(source, target, dirs_exist_ok=True)
p = target / 'Contents/Info.plist'
info = plistlib.loads(p.read_bytes())
info.update(CFBundleIdentifier='com.openly.receiver.uitest', CFBundleName='Openly UI Test', CFBundleDisplayName='Openly UI Test', CFBundleDocumentTypes=[], CFBundleURLTypes=[], OpenlyReceiver=True)
p.write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--sign','-',str(target)],check=True)
print(target)
