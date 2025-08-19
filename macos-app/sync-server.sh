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
    # Don't exit - still need to copy to bundle if in Xcode build
fi

# Only sync if directories are different
if [ -n "$FROM_DIR" ] && [ -n "$TO_DIR" ]; then
    echo "📂 Syncing from $FROM_DIR to $TO_DIR"
    
    # Use rsync to copy, INCLUDING node_modules (single source of truth)
    rsync -av --delete \
      --exclude='coverage' \
      --exclude='.nyc_output' \
      --exclude='*.log' \
      --exclude='test-*.js' \
      --exclude='src/test*' \
      --exclude='.git' \
      --exclude='.gitignore' \
      --exclude='*.test.js' \
      --exclude='server_log.txt' \
      --exclude='.DS_Store' \
      "$FROM_DIR/" "$TO_DIR/"
    
    echo "✅ Server synced successfully"
fi

# Ensure the server has correct permissions
if [ -n "$TO_DIR" ] && [ -d "$TO_DIR" ]; then
    chmod -R 755 "$TO_DIR"
fi

# If we synced back to main, remind to commit changes
if [ "$FROM_DIR" = "$DEST_SERVER" ]; then
    echo ""
    echo "⚠️  IMPORTANT: Changes were synced from Resources back to main server!"
    echo "   Please review and commit these changes to git."
fi

echo "✅ Sync complete"

# Also copy to the build output if we're in a build context
if [ -n "${BUILT_PRODUCTS_DIR}" ] && [ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH}" ]; then
    echo "📦 Copying server to app bundle..."
    BUNDLE_DEST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/server"
    
    # Use the appropriate source directory
    if [ -n "${TO_DIR}" ]; then
        BUNDLE_SOURCE="${TO_DIR}"
    else
        BUNDLE_SOURCE="${SOURCE_SERVER}"
    fi
    
    # Remove old server directory if it exists
    if [ -d "${BUNDLE_DEST}" ]; then
        rm -rf "${BUNDLE_DEST}"
    fi
    
    # Create destination directory
    mkdir -p "${BUNDLE_DEST}"
    
    # Copy server files INCLUDING node_modules (single source of truth)
    # Note: Don't exclude 'dist' as some npm packages need it (e.g., express-rate-limit)
    rsync -av --exclude='.git' \
              --exclude='*.log' \
              --exclude='.env' \
              --exclude='coverage' \
              --exclude='.nyc_output' \
              --exclude='test' \
              --exclude='*.test.js' \
              --exclude='test-*.js' \
              --exclude='src/test*' \
              "${BUNDLE_SOURCE}/" "${BUNDLE_DEST}/"
    
    # Verify node_modules was copied
    if [ -d "${BUNDLE_DEST}/node_modules" ]; then
        echo "✅ Server node_modules successfully included in bundle"
    else
        echo "⚠️ Warning: node_modules not found in bundle!"
    fi
    
    echo "✅ Server bundled in app with all dependencies"
fi