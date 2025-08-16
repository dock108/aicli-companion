#!/bin/bash
# Run tests with keychain unlocked
# Usage: ./test-with-auth.sh [password]

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get password
if [ -n "$1" ]; then
    KEYCHAIN_PASSWORD="$1"
else
    echo -n "Enter keychain password: "
    read -s KEYCHAIN_PASSWORD
    echo
fi

# Unlock keychain
echo "🔓 Unlocking keychain..."
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$HOME/Library/Keychains/login.keychain-db"
security set-keychain-settings -t 10800 -u "$HOME/Library/Keychains/login.keychain-db"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null

echo "🧪 Running tests..."
cd "$SCRIPT_DIR"

# Run tests
xcodebuild test \
    -project AICLICompanionHost.xcodeproj \
    -scheme AICLICompanionHost \
    -destination 'platform=macOS' \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=XC52SAFE3Z \
    CODE_SIGN_IDENTITY="Apple Development" \
    2>&1 | xcbeautify --renderer terminal

echo "✅ Tests complete"