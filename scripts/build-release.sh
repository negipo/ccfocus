#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

cargo build -p ccfocus-logger --release

xcodegen generate --spec ccfocus-app/project.yml --project ccfocus-app/

xcodebuild \
  -project ccfocus-app/ccfocus-app.xcodeproj \
  -scheme ccfocus-app \
  -configuration Release \
  -derivedDataPath build/xcode \
  build

APP_PATH="build/xcode/Build/Products/Release/ccfocus-app.app"
test -d "$APP_PATH" || { echo "app bundle not found: $APP_PATH"; exit 1; }

mkdir -p dist
cp target/release/ccfocus-logger dist/ccfocus-logger
rm -rf dist/ccfocus-app.app
cp -R "$APP_PATH" dist/

echo "logger: dist/ccfocus-logger"
echo "app bundle: dist/ccfocus-app.app"
