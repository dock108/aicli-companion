#!/bin/bash

# Simple macOS icon generator that preserves the original icon appearance
# Just adds proper rounded corners for macOS

INPUT_IMAGE="master-icon.png"
OUTPUT_DIR="output/macos-icons"

mkdir -p "$OUTPUT_DIR/AppIcon.iconset"

echo "Generating macOS icons with rounded corners..."

# Function to create rounded corner icon
create_rounded_icon() {
    local size=$1
    local filename=$2
    
    echo "  Creating $filename (${size}x${size})"
    
    # Calculate proportional corner radius (22.5% of size for macOS standard)
    local radius=$(echo "scale=0; $size * 0.225" | bc)
    
    # Create icon with rounded corners - force square dimensions with padding
    # Add 10% padding on each side (80% of original size)
    local icon_size=$(echo "$size * 8 / 10" | bc)
    local corner_radius=$(echo "$icon_size * 225 / 1000" | bc)
    
    magick "$INPUT_IMAGE" \
        -resize "${icon_size}x${icon_size}!" \
        -background transparent \
        \( +clone -alpha extract \
           -draw "fill black rectangle 0,0 ${icon_size},${icon_size}" \
           -draw "fill white roundrectangle 0,0 $((icon_size-1)),$((icon_size-1)) ${corner_radius},${corner_radius}" \
        \) -alpha off -compose CopyOpacity -composite \
        -gravity center \
        -background transparent \
        -extent "${size}x${size}" \
        "$OUTPUT_DIR/AppIcon.iconset/$filename"
}

# Generate all sizes
create_rounded_icon 16 "icon_16x16.png"
create_rounded_icon 32 "icon_16x16@2x.png"
create_rounded_icon 32 "icon_32x32.png"
create_rounded_icon 64 "icon_32x32@2x.png"
create_rounded_icon 128 "icon_128x128.png"
create_rounded_icon 256 "icon_128x128@2x.png"
create_rounded_icon 256 "icon_256x256.png"
create_rounded_icon 512 "icon_256x256@2x.png"
create_rounded_icon 512 "icon_512x512.png"
create_rounded_icon 1024 "icon_512x512@2x.png"

echo "Creating ICNS file..."
iconutil -c icns "$OUTPUT_DIR/AppIcon.iconset" -o "$OUTPUT_DIR/AppIcon.icns"

if [ $? -eq 0 ]; then
    echo "✅ Successfully created AppIcon.icns"
else
    echo "❌ Failed to create ICNS file"
fi