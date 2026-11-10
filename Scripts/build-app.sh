#!/bin/bash
# Builds a Release "RSS Reader.app" for macOS into build/ (signed to run locally unless a team is set).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project RSSReader.xcodeproj -scheme RSSReader -configuration Release \
    -destination 'platform=macOS' -derivedDataPath build/dd -quiet build

rm -rf "build/RSS Reader.app"
cp -R "build/dd/Build/Products/Release/RSS Reader.app" build/
echo "Built build/RSS Reader.app"
