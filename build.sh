#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AudioSampler"
BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"

echo "Building AudioSampler (release)..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

BINARY="$(swift build -c release --show-bin-path)/AudioSampler"

echo "Assembling ${APP_NAME}.app..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BINARY" "$BUNDLE/Contents/MacOS/AudioSampler"
cp "$SCRIPT_DIR/Info.plist" "$BUNDLE/Contents/"

echo ""
echo "Built: ${BUNDLE}"
echo ""

if [ -d "/Applications/${APP_NAME}.app" ]; then
    echo "Removing old installation..."
    rm -rf "/Applications/${APP_NAME}.app"
fi
cp -R "$BUNDLE" "/Applications/${APP_NAME}.app"
echo "Installed to /Applications/${APP_NAME}.app"

killall AudioSampler 2>/dev/null || true
echo "Launching ${APP_NAME}..."
open "/Applications/${APP_NAME}.app"
