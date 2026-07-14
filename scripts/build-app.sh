#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Owl Codex Monitor"
ARM64_BUILD_DIR="$ROOT/.build/arm64-apple-macosx/release"
X86_64_BUILD_DIR="$ROOT/.build/x86_64-apple-macosx/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"

cd "$ROOT"
swift build -c release --arch arm64
swift build -c release --arch x86_64

rm -rf "$ROOT/dist"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
lipo -create \
  "$ARM64_BUILD_DIR/OwlCodexMonitor" \
  "$X86_64_BUILD_DIR/OwlCodexMonitor" \
  -output "$APP_DIR/Contents/MacOS/OwlCodexMonitor"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>OwlCodexMonitor</string>
  <key>CFBundleIdentifier</key>
  <string>tech.owlai.codex-monitor</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Owl Codex Monitor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.5</string>
  <key>CFBundleVersion</key>
  <string>6</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
