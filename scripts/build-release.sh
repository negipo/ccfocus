#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

cargo build -p ccsplit-logger --release

xcodegen generate --spec ccsplit-app/project.yml --project ccsplit-app/

xcodebuild \
  -project ccsplit-app/ccsplit-app.xcodeproj \
  -scheme ccsplit-app \
  -configuration Release \
  -derivedDataPath build/xcode \
  build

APP_PATH="build/xcode/Build/Products/Release/ccsplit-app.app"
test -d "$APP_PATH" || { echo "app bundle not found: $APP_PATH"; exit 1; }

mkdir -p dist
cp target/release/ccsplit-logger dist/ccsplit-logger
rm -rf dist/ccsplit-app.app
cp -R "$APP_PATH" dist/

echo "logger: dist/ccsplit-logger"
echo "app bundle: dist/ccsplit-app.app"
