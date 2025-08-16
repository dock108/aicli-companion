#!/bin/bash
# Clean build script for AICLICompanionHost
# This ensures all changes are properly included in the build

set -e

echo "🧹 Cleaning Xcode build artifacts..."
xcodebuild clean -project AICLICompanionHost.xcodeproj -configuration Debug
xcodebuild clean -project AICLICompanionHost.xcodeproj -configuration Release

echo "🗑️  Removing derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/AICLICompanionHost-*

echo "🔄 Running server sync..."
./sync-server.sh

echo "✅ Clean complete! Now you can build in Xcode."
echo ""
echo "The QR code will now show the complete WebSocket URL with:"
echo "  - WebSocket protocol (ws:// or wss://)"
echo "  - /ws path"
echo "  - Auth token as query parameter (if authentication is enabled)"
echo ""
echo "Example: wss://abc123.ngrok-free.app/ws?token=<your-token>"