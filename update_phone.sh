#!/bin/bash
set -e

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

echo "🔍 Checking for connected iPhone..."
DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep "physical" | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}' | head -n 1)

if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID="00008150-00154999228A401C"
fi

echo "📱 Target iPhone: $DEVICE_ID"
echo "🔨 Building latest TripperDash code..."

xcodebuild \
  -project TripperDash.xcodeproj \
  -scheme TripperDash \
  -destination "generic/platform=iOS" \
  -quiet build

APP_PATH="/Users/aniketh/Library/Developer/Xcode/DerivedData/TripperDash-hfrxwiolcnhmqlghaegjynugshmy/Build/Products/Debug-iphoneos/TripperDash.app"

echo "📲 Installing app to iPhone..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "🚀 Launching TripperDash on iPhone..."
xcrun devicectl device process launch --device "$DEVICE_ID" com.aniketh.tripperdash

echo "🎉 Done! TripperDash has been updated and launched on your iPhone."
