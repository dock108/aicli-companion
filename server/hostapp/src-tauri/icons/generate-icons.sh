#!/bin/bash

# Script to generate all required icon sizes from a source image
# Usage: ./generate-icons.sh source-icon.png

if [ -z "$1" ]; then
    echo "Usage: $0 <source-icon-file>"
    echo "Source icon should ideally be 512x512 or larger"
    exit 1
fi

SOURCE="$1"

if [ ! -f "$SOURCE" ]; then
    echo "Error: Source file '$SOURCE' not found"
    exit 1
fi

echo "Generating icons from $SOURCE..."

# Use sips (built-in macOS tool) to generate all required sizes
sips -z 512 512 "$SOURCE" --out icon.png
sips -z 256 256 "$SOURCE" --out 128x128@2x.png
sips -z 128 128 "$SOURCE" --out 128x128.png
sips -z 32 32 "$SOURCE" --out 32x32.png

echo "Icon generation complete!"
echo "Generated files:"
ls -la *.png