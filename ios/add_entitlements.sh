#!/bin/bash

# Add entitlements to Xcode project
echo "Adding APNS entitlements to Xcode project..."

# Path to the entitlements file
ENTITLEMENTS_PATH="App/AICLICompanion.entitlements"

# Update the Xcode project using xcodebuild or xcrun
# This requires manual intervention in Xcode

cat << EOF

=================================================================
MANUAL STEPS REQUIRED:
=================================================================

Please open the iOS project in Xcode and follow these steps:

1. Open /Users/michaelfuscoletti/Desktop/claude-companion/ios/AICLICompanion.xcodeproj

2. Select the AICLICompanion target

3. Go to the "Signing & Capabilities" tab

4. Click the "+" button to add a capability

5. Add "Push Notifications" capability

6. In Build Settings, search for "Code Signing Entitlements"

7. Set the value to: App/AICLICompanion.entitlements

8. Build and run the app

The entitlements file has already been created at:
$ENTITLEMENTS_PATH

with the following content:
- aps-environment: development
- com.apple.developer.aps-environment: development

=================================================================
EOF