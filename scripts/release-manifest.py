#!/usr/bin/env python3
import json
import sys
from pathlib import Path

mode, version, build, repo = sys.argv[1:]
Path('dist/release.json').write_text(json.dumps({
    'version': version, 'build': build, 'repository': repo,
    'developerIDSignedAndNotarized': mode == 'release',
    'applications': ['Screener Server.app', 'Screener Client.app'],
}, indent=2) + '\n')
