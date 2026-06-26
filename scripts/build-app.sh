#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release

APP_DIR="$ROOT_DIR/.build/Peeky.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/.build/release/Peeky" "$APP_DIR/Contents/MacOS/Peeky"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/Peeky.icns" "$APP_DIR/Contents/Resources/Peeky.icns"
chmod +x "$APP_DIR/Contents/MacOS/Peeky"

echo "$APP_DIR"
