#!/bin/bash

# Script to generate macOS-compliant app icons with rounded corners and shadow
# Based on Apple's specifications: 824x824 icon with 185.4px corner radius on 1024x1024 canvas

# Check if ImageMagick is installed
if ! command -v magick &> /dev/null; then
    echo "ImageMagick is required but not installed. Install it with: brew install imagemagick"
    exit 1
fi

INPUT_IMAGE="master-icon.png"
OUTPUT_DIR="output/macos-icons"

# Create output directory
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/AppIcon.iconset"

echo "Generating macOS App Icons with rounded corners..."

# Function to create a rounded rectangle mask with the macOS standard corner radius
create_macos_icon() {
    local size=$1
    local output_name=$2
    local icon_size=$((size * 824 / 1024))  # Scale the 824px icon size proportionally
    local padding=$(((size - icon_size) / 2))  # Calculate padding
    local corner_radius=$(echo "scale=2; $icon_size * 185.4 / 824" | bc)  # Scale corner radius proportionally
    
    echo "  Creating $output_name (${size}x${size}) with ${icon_size}x${icon_size} icon, corner radius: $corner_radius"
    
    # Create the icon with rounded corners
    # Create a temporary file for the resized image
    local temp_resized="/tmp/icon_resized_$$.png"
    
    # First resize the image
    magick "$INPUT_IMAGE" -resize "${icon_size}x${icon_size}!" "$temp_resized"
    
    # Create the final icon with rounded corners
    magick -size ${size}x${size} xc:transparent \
        \( "$temp_resized" \
           \( +clone -alpha extract \
              -draw "fill black rectangle 0,0 ${icon_size},${icon_size}" \
              -draw "fill white roundrectangle 0,0 $((icon_size-1)),$((icon_size-1)) ${corner_radius},${corner_radius}" \
           \) -alpha off -compose CopyOpacity -composite \
        \) -gravity center -composite \
        "$OUTPUT_DIR/AppIcon.iconset/$output_name"
    
    # Clean up
    rm -f "$temp_resized"
}

# Generate all required sizes for macOS iconset
# Format: size:filename
ICON_SIZES=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for size_info in "${ICON_SIZES[@]}"; do
    IFS=':' read -r size filename <<< "$size_info"
    create_macos_icon "$size" "$filename"
done

echo ""
echo "Creating ICNS file..."

# Create the ICNS file from the iconset
iconutil -c icns "$OUTPUT_DIR/AppIcon.iconset" -o "$OUTPUT_DIR/AppIcon.icns"

if [ $? -eq 0 ]; then
    echo "✅ Successfully created AppIcon.icns"
    echo ""
    echo "Generated files:"
    echo "  - $OUTPUT_DIR/AppIcon.icns (for Tauri app)"
    echo "  - $OUTPUT_DIR/AppIcon.iconset/ (individual PNG files)"
    echo ""
    echo "Next steps:"
    echo "1. Copy AppIcon.icns to server/hostapp/src-tauri/icons/"
    echo "2. Update tauri.conf.json to use AppIcon.icns for macOS"
else
    echo "❌ Failed to create ICNS file"
    exit 1
fi