#!/bin/bash
# Unlock keychain for build session
# Usage: ./unlock-keychain.sh [password]

KEYCHAIN_NAME="login.keychain-db"
KEYCHAIN_PATH="$HOME/Library/Keychains/$KEYCHAIN_NAME"

# If password provided as argument, use it; otherwise prompt
if [ -n "$1" ]; then
    KEYCHAIN_PASSWORD="$1"
else
    echo -n "Enter keychain password: "
    read -s KEYCHAIN_PASSWORD
    echo
fi

# Unlock the keychain
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

if [ $? -eq 0 ]; then
    echo "✅ Keychain unlocked successfully"
    
    # Set keychain to stay unlocked for 3 hours (10800 seconds)
    security set-keychain-settings -t 10800 -u "$KEYCHAIN_PATH"
    echo "⏱️  Keychain will stay unlocked for 3 hours"
    
    # Allow codesign to access keychain without prompting
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" 2>/dev/null
    echo "🔓 Codesigning access granted"
else
    echo "❌ Failed to unlock keychain"
    exit 1
fi