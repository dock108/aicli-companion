#!/bin/bash
# Run tests using environment variables
# Expects .env file or KEYCHAIN_PASSWORD environment variable

set -e
cd "$(dirname "$0")"

# Load .env if it exists
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Check for password
if [ -z "$KEYCHAIN_PASSWORD" ]; then
    echo "❌ KEYCHAIN_PASSWORD not set"
    echo "Set it in .env file or as environment variable"
    exit 1
fi

# Unlock keychain
echo "🔓 Unlocking keychain..."
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$HOME/Library/Keychains/login.keychain-db"
security set-keychain-settings -t 10800 -u "$HOME/Library/Keychains/login.keychain-db"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null

echo "🧪 Running tests..."

xcodebuild test \
    -project AICLICompanionHost.xcodeproj \
    -scheme AICLICompanionHost \
    -destination 'platform=macOS' \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-XC52SAFE3Z}" \
    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}" \
    2>&1 | xcbeautify --renderer terminal

echo "✅ Tests complete"