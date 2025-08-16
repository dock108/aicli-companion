#!/bin/bash

# Smart sync script for server - detects which version is newer
# and syncs from the newer source to ensure we don't lose changes

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SOURCE_SERVER="$SCRIPT_DIR/../server"
DEST_SERVER="$SCRIPT_DIR/AICLICompanionHost/Resources/server"

echo "🔍 Checking server versions..."

# Function to get the most recent modification time in a directory
get_latest_mod_time() {
    local dir="$1"
    if [ -d "$dir" ]; then
        find "$dir" -type f -name "*.js" -not -path "*/node_modules/*" -not -path "*/coverage/*" -not -path "*/.nyc_output/*" -exec stat -f "%m" {} \; 2>/dev/null | sort -n | tail -1
    else
        echo "0"
    fi
}

# Get modification times
SOURCE_TIME=$(get_latest_mod_time "$SOURCE_SERVER")
DEST_TIME=$(get_latest_mod_time "$DEST_SERVER")

# If destination doesn't exist, just sync from source
if [ ! -d "$DEST_SERVER" ]; then
    echo "📦 Creating initial server bundle from $SOURCE_SERVER"
    mkdir -p "$DEST_SERVER"
    SOURCE_TIME=1
    DEST_TIME=0
fi

# Determine sync direction
if [ "$SOURCE_TIME" -gt "$DEST_TIME" ]; then
    echo "✅ Main server is newer - syncing to Resources"
    FROM_DIR="$SOURCE_SERVER"
    TO_DIR="$DEST_SERVER"
elif [ "$DEST_TIME" -gt "$SOURCE_TIME" ]; then
    echo "⚠️  Resources server is newer - syncing back to main"
    echo "   This might happen if you edited files directly in Xcode"
    FROM_DIR="$DEST_SERVER"
    TO_DIR="$SOURCE_SERVER"
else
    echo "✅ Servers are in sync"
    exit 0
fi

echo "📂 Syncing from $FROM_DIR to $TO_DIR"

# Use rsync to copy, excluding unnecessary files
rsync -av --delete \
  --exclude='node_modules' \
  --exclude='coverage' \
  --exclude='.nyc_output' \
  --exclude='*.log' \
  --exclude='test-*.js' \
  --exclude='src/test*' \
  --exclude='.git' \
  --exclude='.gitignore' \
  --exclude='*.test.js' \
  --exclude='hostapp' \
  --exclude='server_log.txt' \
  --exclude='.DS_Store' \
  "$FROM_DIR/" "$TO_DIR/"

echo "✅ Server synced successfully"

# Ensure the server has correct permissions
chmod -R 755 "$TO_DIR"

# If we synced back to main, remind to commit changes
if [ "$FROM_DIR" = "$DEST_SERVER" ]; then
    echo ""
    echo "⚠️  IMPORTANT: Changes were synced from Resources back to main server!"
    echo "   Please review and commit these changes to git."
fi

echo "✅ Sync complete"