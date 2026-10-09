#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
swift scripts/make-icons.swift
for role in Server Client; do
  if ! iconutil -c icns "Assets/Screener$role.iconset" -o "Assets/Screener$role.icns"; then
    # Some restricted sessions cannot contact iconutil's conversion service.
    python3 scripts/write-icns.py "Assets/Screener$role.iconset" "Assets/Screener$role.icns"
  fi
  rm -rf "Assets/Screener$role.iconset"
done
