#!/usr/bin/env python3
import struct
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
entries = [
    ('icp4', 'icon_16x16.png', 16), ('icp5', 'icon_32x32.png', 32),
    ('icp6', 'icon_32x32@2x.png', 64), ('ic07', 'icon_128x128.png', 128),
    ('ic08', 'icon_256x256.png', 256), ('ic09', 'icon_512x512.png', 512),
    ('ic10', 'icon_512x512@2x.png', 1024), ('ic11', 'icon_16x16@2x.png', 32),
    ('ic12', 'icon_32x32@2x.png', 64), ('ic13', 'icon_128x128@2x.png', 256),
    ('ic14', 'icon_256x256@2x.png', 512),
]
chunks = []
for kind, filename, size in entries:
    data = (source / filename).read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', data[16:24]) != (size, size):
        raise SystemExit(f'Invalid icon image: {filename}')
    chunks.append(kind.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
destination.write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
