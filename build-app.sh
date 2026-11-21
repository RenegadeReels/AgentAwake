#!/bin/bash
# Builds AgentAwake.app. Pass --install to also copy it to /Applications and open it.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Run: xcode-select --install   (then run this script again)"
  exit 1
fi

echo "Building…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/AgentAwake.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AgentAwake" "$APP/Contents/MacOS/AgentAwake"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>AgentAwake</string>
  <key>CFBundleDisplayName</key><string>AgentAwake</string>
  <key>CFBundleIdentifier</key><string>app.agentawake.AgentAwake</string>
  <key>CFBundleExecutable</key><string>AgentAwake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>AgentAwake asks for your admin password to change sleep settings.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x AgentAwake 2>/dev/null || true
  rm -rf /Applications/AgentAwake.app
  cp -R "$APP" /Applications/
  open /Applications/AgentAwake.app
  echo "Installed to /Applications and launched. Look for the moon icon in your menu bar."
fi
