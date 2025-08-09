# Adding Server to Xcode Project

## Steps to add server folder as a resource:

1. Open `AICLICompanionHost.xcodeproj` in Xcode

2. Right-click on the `Resources` folder in the project navigator

3. Select "Add Files to 'AICLICompanionHost'..."

4. Navigate to `/Users/michaelfuscoletti/Desktop/claude-companion/server`

5. **IMPORTANT**: 
   - Check "Copy items if needed" (or create a symlink)
   - Select "Create folder references" (NOT "Create groups")
   - Make sure "AICLICompanionHost" target is checked

6. Click "Add"

The server folder will appear as a blue folder icon (folder reference) rather than yellow (group). This means:
- The entire folder structure will be copied to Resources
- Any changes to the server folder will be included in builds
- No need to manually update when files change

## Alternative: Add Build Phase Script

If the folder reference doesn't work, add a Run Script build phase:

1. Select the AICLICompanionHost target
2. Go to Build Phases tab
3. Click + → New Run Script Phase
4. Add this script:

```bash
# Copy server to Resources
SOURCE="${PROJECT_DIR}/../server"
DEST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/server"

# Remove old server if exists
rm -rf "$DEST"

# Copy server (excluding node_modules)
rsync -av --exclude='node_modules' \
          --exclude='.git' \
          --exclude='*.log' \
          "$SOURCE/" "$DEST/"
```

5. Rename the phase to "Copy Server Files"
6. Drag it to run after "Copy Bundle Resources"

## Why Folder Reference is Better:

- Automatic: Xcode handles the copying
- Clean: Shows in project navigator
- Reliable: Works with archiving and distribution
- Simple: No script maintenance needed