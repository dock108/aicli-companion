# Build Instructions - UI Changes and Assets

## Clean Build Steps

To ensure all UI changes and assets are properly reflected in your app:

1. **Clean Build Folder in Xcode:**
   - Open the project in Xcode
   - Go to Product → Clean Build Folder (Shift+Cmd+K)
   - Alternatively: `rm -rf ~/Library/Developer/Xcode/DerivedData/ClaudeCompanion*`

2. **Reset Package Cache:**
   ```bash
   cd /Users/michaelfuscoletti/Desktop/claude-companion/ios
   rm -rf .build
   rm -rf build
   ```

3. **Rebuild the Project:**
   - In Xcode: Product → Build (Cmd+B)
   - Or from command line:
   ```bash
   xcodebuild clean build -project ClaudeCompanion.xcodeproj -scheme ClaudeCompanionApp
   ```

4. **If Assets Still Don't Appear:**
   - Delete the app from the simulator
   - Reset the simulator: Device → Erase All Content and Settings
   - Build and run again

## Changes Made

1. **Removed Test Button** - The debug test button has been removed from ConnectionView
2. **Added Assets** - App icon and logo assets are now properly included in the project
3. **UI Overhaul** - New gradient background and custom header with logo
4. **Fixed Asset References** - Both Xcode project and Swift Package Manager now properly reference the assets

## Verification

After building, you should see:
- App icon on the home screen
- Logo in the app header (light/dark mode variants)
- Gradient background
- No test button in the connection view
- Cleaner, single-screen UI design