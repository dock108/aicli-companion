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

# Copy server files (excluding node_modules and other unnecessary files)
rsync -av --exclude='node_modules' \
          --exclude='.git' \
          --exclude='*.log' \
          --exclude='.env' \
          --exclude='coverage' \
          --exclude='.nyc_output' \
          --exclude='dist' \
          --exclude='build' \
          "${SOURCE_DIR}/" "${DEST_DIR}/"

echo "Server files copied successfully"

# Install npm dependencies in the bundled server
echo "Installing server dependencies..."
cd "${DEST_DIR}"
npm ci --production --silent

echo "Server bundling complete"