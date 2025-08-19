#!/bin/bash

# Copy server files to app bundle
# This script is run as a build phase in Xcode

set -e

# Get the source and destination paths
SOURCE_DIR="${PROJECT_DIR}/../server"
DEST_DIR="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/server"

echo "Copying server from: ${SOURCE_DIR}"
echo "To: ${DEST_DIR}"

# Remove old server directory if it exists
if [ -d "${DEST_DIR}" ]; then
    rm -rf "${DEST_DIR}"
fi

# Create destination directory
mkdir -p "${DEST_DIR}"

# Copy server files INCLUDING node_modules (single source of truth)
# Note: Don't exclude 'dist' as some npm packages need it (e.g., express-rate-limit)
rsync -av --exclude='.git' \
          --exclude='*.log' \
          --exclude='.env' \
          --exclude='coverage' \
          --exclude='.nyc_output' \
          --exclude='test' \
          --exclude='*.test.js' \
          --exclude='src/test*' \
          "${SOURCE_DIR}/" "${DEST_DIR}/"

echo "Server bundling complete"