#!/usr/bin/env python3
import base64
import email.utils
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

role, archive, version, build, repo, signature = sys.argv[1:]
if role not in ('Server', 'Client') or not re.fullmatch(r'[\w.-]+/[\w.-]+', repo):
    raise SystemExit('Invalid appcast role/repository')
if len(base64.b64decode(signature, validate=True)) != 64:
    raise SystemExit('Invalid update signature')
sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', sparkle)
rss = ET.Element('rss', version='2.0')
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = f'Screener {role} Updates'
ET.SubElement(channel, 'link').text = f'https://github.com/{repo}'
ET.SubElement(channel, 'description').text = f'Updates for Screener {role} on Apple silicon Macs.'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'Screener {role} {version}'
ET.SubElement(item, 'pubDate').text = email.utils.formatdate(usegmt=True)
ET.SubElement(item, f'{{{sparkle}}}version').text = build
ET.SubElement(item, f'{{{sparkle}}}shortVersionString').text = version
ET.SubElement(item, f'{{{sparkle}}}minimumSystemVersion').text = '15.0'
ET.SubElement(item, 'description').text = '4K remote desktop with macOS HiDPI scaling. See the GitHub release for details.'
path = Path(archive)
ET.SubElement(item, 'enclosure', {
    'url': f'https://github.com/{repo}/releases/download/v{version}/{path.name}',
    'length': str(path.stat().st_size), 'type': 'application/octet-stream',
    f'{{{sparkle}}}edSignature': signature,
})
ET.indent(rss, space='  ')
ET.ElementTree(rss).write(f'dist/feeds/{role.lower()}.xml', encoding='utf-8', xml_declaration=True)
