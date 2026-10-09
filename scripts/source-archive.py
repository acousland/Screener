#!/usr/bin/env python3
import zipfile
from pathlib import Path

version = Path('VERSION').read_text().strip()
destination = Path('dist') / f'Screener-source-{version}.zip'
directories = ['Sources', 'Tests', 'scripts', 'Assets', 'docs', '.github', 'feeds']
files = [Path(name) for name in ['Package.swift', 'VERSION', 'README.md', 'LICENSE', '.gitignore']]
for directory in directories:
    files.extend(p for p in Path(directory).rglob('*') if p.is_file() and not p.name.startswith('.DS_Store'))
for path in files:
    if any(part in {'.secrets', '.build', '.git', 'Vendor', 'dist'} for part in path.parts):
        raise SystemExit('Refusing to include private/build files in the source archive')
with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(files):
        archive.write(path, Path(f'Screener-{version}') / path)
print(f'Wrote {destination} ({len(files)} source files; no credentials or build products).')
