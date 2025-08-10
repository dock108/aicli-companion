# Bundling Server with macOS App

## Manual Process (Current)

Until we add a proper build phase to Xcode, follow these steps to bundle the server:

1. Copy the server to Resources:
```bash
cp -r ../server AICLICompanionHost/Resources/
```

2. Remove node_modules (will be installed on first run):
```bash
rm -rf AICLICompanionHost/Resources/server/node_modules
```

3. Build the app in Xcode

## Automatic Process (TODO)

Add a Run Script build phase to Xcode project:
1. Open project in Xcode
2. Select AICLICompanionHost target
3. Go to Build Phases
4. Add New Run Script Phase
5. Use the script in `copy-server.sh`

## How It Works

The app now:
- Bundles the server code in Resources/server
- Uses `Bundle.main.resourcePath` to find the server
- Installs npm dependencies on first run if needed
- No user configuration needed for server location