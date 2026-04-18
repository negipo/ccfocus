#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

cargo build -p ccfocus-logger --release

xcodegen generate --spec ccfocus-app/project.yml --project ccfocus-app/

ORIG_PLIST="ccfocus-app/ccfocus-app/Info.plist"
if [ -n "${VERSION:-}" ]; then
  cp "$ORIG_PLIST" "${ORIG_PLIST}.bak"
  trap 'mv "${ORIG_PLIST}.bak" "$ORIG_PLIST" 2>/dev/null || true' EXIT
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$ORIG_PLIST"
fi

xcodebuild \
  -project ccfocus-app/ccfocus-app.xcodeproj \
  -scheme ccfocus-app \
  -configuration Release \
  -derivedDataPath build/xcode \
  build

APP_PATH="build/xcode/Build/Products/Release/ccfocus-app.app"
test -d "$APP_PATH" || { echo "app bundle not found: $APP_PATH"; exit 1; }

mkdir -p "$APP_PATH/Contents/Resources/bin"
cp target/release/ccfocus-logger "$APP_PATH/Contents/Resources/bin/ccfocus-logger"

codesign --force --sign - "$APP_PATH/Contents/Resources/bin/ccfocus-logger"
codesign --force --sign - "$APP_PATH"
codesign --verify --verbose "$APP_PATH"

mkdir -p dist
cp target/release/ccfocus-logger dist/ccfocus-logger
rm -rf dist/ccfocus-app.app
cp -R "$APP_PATH" dist/

if [ -n "${VERSION:-}" ]; then
  command -v create-dmg >/dev/null || { echo "create-dmg required; brew install create-dmg" >&2; exit 1; }
  DMG_NAME="ccfocus-${VERSION}-macos.dmg"
  rm -f "$DMG_NAME"
  create-dmg \
    --volname "ccfocus" \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "ccfocus-app.app" 150 200 \
    --app-drop-link 450 200 \
    --no-internet-enable \
    "$DMG_NAME" "$APP_PATH"
  echo "dmg: $DMG_NAME"
fi

echo "logger: dist/ccfocus-logger"
echo "app bundle: dist/ccfocus-app.app"
