#!/bin/bash

# Script to add the sync-server build phase to Xcode project
# This needs to be run once to set up the project

echo "📱 Adding server sync build phase to Xcode project..."

cat << 'EOF'

MANUAL STEPS TO ADD BUILD PHASE IN XCODE:

1. Open AICLICompanionHost.xcodeproj in Xcode

2. Select the "AICLICompanionHost" target (not the project)

3. Go to the "Build Phases" tab

4. Click the "+" button at the top and choose "New Run Script Phase"

5. Rename it to "Sync Server Bundle" (double-click the name)

6. Drag it to run BEFORE "Copy Bundle Resources" phase

7. In the script editor, add:
   "${SRCROOT}/sync-server.sh"

8. Uncheck "Based on dependency analysis" if present

9. Optional: Check "Show environment variables in build log" for debugging

That's it! The server will now sync automatically before each build.

To test it works:
- Make a change to any .js file in /server
- Build the app in Xcode
- Check the build log for sync messages

EOF

echo ""
echo "✅ Instructions printed above. Follow them in Xcode to complete setup."