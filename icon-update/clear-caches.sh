#!/bin/bash

echo "Clearing Xcode and app caches..."

# Clear Xcode derived data
echo "1. Clearing Xcode derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Clear iOS Simulator caches
echo "2. Clearing iOS Simulator caches..."
xcrun simctl shutdown all
rm -rf ~/Library/Developer/CoreSimulator/Caches/dyld/*

# Clear the specific app's build folder
echo "3. Clearing local build folder..."
cd /Users/michaelfuscoletti/Desktop/claude-companion/ios
rm -rf build/
rm -rf DerivedData/

# For the Tauri app
echo "4. Clearing Tauri app cache..."
cd /Users/michaelfuscoletti/Desktop/claude-companion/server/hostapp
rm -rf target/
rm -rf src-tauri/target/

echo ""
echo "✅ Caches cleared!"
echo ""
echo "Next steps:"
echo "1. Open Xcode"
echo "2. Clean build folder (Cmd+Shift+K)"
echo "3. Delete app from simulator/device"
echo "4. Build and run again"
echo ""
echo "For Tauri app:"
echo "1. Run: npm run tauri build"
echo "2. Or: npm run tauri dev"