#!/usr/bin/env python3
import base64
import plistlib
import re
import sys
from pathlib import Path

role, destination, version, build, repo = sys.argv[1:]
if role not in ('Server', 'Client') or not re.fullmatch(r'[\w.-]+/[\w.-]+', repo):
    raise SystemExit('Invalid role or GitHub repository')
key = Path('Assets/update-public-key').read_text().strip()
if len(base64.b64decode(key, validate=True)) != 32:
    raise SystemExit('Invalid Sparkle public key')
info = {
    'CFBundleName': f'Screener {role}', 'CFBundleDisplayName': f'Screener {role}',
    'CFBundleIdentifier': f'au.com.acousland.Screener{role}', 'CFBundleExecutable': f'Screener{role}',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version, 'CFBundleVersion': build,
    'CFBundleIconFile': f'Screener{role}', 'LSMinimumSystemVersion': '15.0', 'NSHighResolutionCapable': True,
    'NSHumanReadableCopyright': 'Copyright © 2026 Aaron Cousland. MIT licence.',
    'NSLocalNetworkUsageDescription': 'Screener discovers and connects to your Mac mini directly on your local network.',
    'NSBonjourServices': ['_screener._tcp'],
    'SUFeedURL': f'https://raw.githubusercontent.com/{repo}/main/feeds/{role.lower()}.xml',
    'SUPublicEDKey': key, 'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
    'SUEnableAutomaticChecks': True, 'SUAutomaticallyUpdate': False,
}
if role == 'Client': info['NSPrincipalClass'] = 'ScreenerApplication'
if role == 'Server':
    info['NSScreenCaptureUsageDescription'] = 'Screener shares the selected desktop with your connected MacBook.'
    info['NSAudioCaptureUsageDescription'] = "Screener sends the mini's system audio to your connected MacBook."
Path(destination).write_bytes(plistlib.dumps(info))
