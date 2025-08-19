# Build Instructions for macOS App

## Server Synchronization

The macOS app bundles the Node.js server from `/server` directory. The bundled copy in Resources is automatically generated and should not be edited directly.

### Automatic Sync in Xcode (Required)

The sync script intelligently detects which version is newer and syncs accordingly:
- If `/server` is newer → syncs to Resources
- If Resources is newer (e.g., you edited in Xcode) → syncs back to `/server`

To set up automatic syncing in Xcode:

1. Open `AICLICompanionHost.xcodeproj` in Xcode
2. Select the `AICLICompanionHost` target (not the project)
3. Go to the **Build Phases** tab
4. Click the **+** button and choose **"New Run Script Phase"**
5. Rename it to **"Sync Server Bundle"** (double-click the name)
6. **IMPORTANT**: Drag it to run **BEFORE** "Copy Bundle Resources"
7. In the script editor, add:
   ```bash
   "${SRCROOT}/sync-server.sh"
   ```
8. Uncheck "Based on dependency analysis" if present
9. Optional: Check "Show environment variables in build log" for debugging

### Manual Sync
If you need to manually sync the server:

```bash
cd macos-app
./sync-server.sh
```

The script will automatically detect which version is newer and sync in the appropriate direction.

## Important Notes

- **Source of Truth**: The main server at `/server` is the primary source
- **Generated Bundle**: `/macos-app/AICLICompanionHost/Resources/server` is auto-generated
- **Git Ignored**: The Resources/server directory is in .gitignore (don't commit it)
- **Smart Sync**: The script detects which version is newer and syncs accordingly
- **Exclusions**: Test files, node_modules, and coverage files are automatically excluded
- **Configuration**: The `.c8rc.json` and `package.json` are maintained in `/server`

## Testing the Setup

1. Make a change to any `.js` file in `/server`
2. Build the app in Xcode (⌘+B)
3. Check the build log for sync messages
4. The server will be automatically synced to Resources

## Troubleshooting

If the sync script isn't running:
- Make sure `sync-server.sh` is executable: `chmod +x sync-server.sh`
- Check that the build phase is BEFORE "Copy Bundle Resources"
- Look for sync messages in the Xcode build log