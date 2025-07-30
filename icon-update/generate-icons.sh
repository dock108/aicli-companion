#!/bin/bash

# Script to generate all required icon sizes for iOS app
# Requires ImageMagick to be installed: brew install imagemagick

# Check if master icon exists
if [ ! -f "master-icon.png" ]; then
    echo "Error: master-icon.png not found!"
    echo "Please place your 1024x1024 master icon in this directory"
    exit 1
fi

# Create output directory
mkdir -p output/ios-icons
mkdir -p output/app-logos
mkdir -p output/server-icons

# iOS App Icon sizes
echo "Generating iOS App Icons..."

# iPhone Notification - 20pt
convert master-icon.png -resize 40x40! -gravity center -extent 40x40 output/ios-icons/icon-20@2x.png
convert master-icon.png -resize 60x60! -gravity center -extent 60x60 output/ios-icons/icon-20@3x.png

# iPhone Settings - 29pt  
convert master-icon.png -resize 58x58! -gravity center -extent 58x58 output/ios-icons/icon-29@2x.png
convert master-icon.png -resize 87x87! -gravity center -extent 87x87 output/ios-icons/icon-29@3x.png

# iPhone Spotlight - 40pt
convert master-icon.png -resize 80x80! -gravity center -extent 80x80 output/ios-icons/icon-40@2x.png
convert master-icon.png -resize 120x120! -gravity center -extent 120x120 output/ios-icons/icon-40@3x.png

# iPhone App - 60pt
convert master-icon.png -resize 120x120! -gravity center -extent 120x120 output/ios-icons/icon-60@2x.png
convert master-icon.png -resize 180x180! -gravity center -extent 180x180 output/ios-icons/icon-60@3x.png

# iPad Notifications - 20pt
convert master-icon.png -resize 20x20! -gravity center -extent 20x20 output/ios-icons/icon-20.png
convert master-icon.png -resize 40x40! -gravity center -extent 40x40 output/ios-icons/icon-20@2x.png

# iPad Settings - 29pt
convert master-icon.png -resize 29x29! -gravity center -extent 29x29 output/ios-icons/icon-29.png
convert master-icon.png -resize 58x58! -gravity center -extent 58x58 output/ios-icons/icon-29@2x.png

# iPad Spotlight - 40pt
convert master-icon.png -resize 40x40! -gravity center -extent 40x40 output/ios-icons/icon-40.png
convert master-icon.png -resize 80x80! -gravity center -extent 80x80 output/ios-icons/icon-40@2x.png

# iPad App - 76pt
convert master-icon.png -resize 76x76! -gravity center -extent 76x76 output/ios-icons/icon-76.png
convert master-icon.png -resize 152x152! -gravity center -extent 152x152 output/ios-icons/icon-76@2x.png

# iPad Pro App - 83.5pt
convert master-icon.png -resize 167x167! -gravity center -extent 167x167 output/ios-icons/icon-83.5@2x.png

# App Store
convert master-icon.png -resize 1024x1024! -gravity center -extent 1024x1024 output/ios-icons/icon-1024.png

echo "iOS App Icons generated!"

# App Logo variants (for in-app use)
echo "Generating App Logo variants..."

# Standard logo sizes
convert master-icon.png -resize 120x120! -gravity center -extent 120x120 output/app-logos/logo.png
convert master-icon.png -resize 240x240! -gravity center -extent 240x240 output/app-logos/logo@2x.png
convert master-icon.png -resize 360x360! -gravity center -extent 360x360 output/app-logos/logo@3x.png

# Dark mode variants (same as light for now)
cp output/app-logos/logo.png output/app-logos/logo-dark.png
cp output/app-logos/logo@2x.png output/app-logos/logo-dark@2x.png
cp output/app-logos/logo@3x.png output/app-logos/logo-dark@3x.png

echo "App Logo variants generated!"

# Server/Tauri icons
echo "Generating server icons..."

convert master-icon.png -resize 32x32 output/server-icons/32x32.png
convert master-icon.png -resize 128x128 output/server-icons/128x128.png
convert master-icon.png -resize 256x256 output/server-icons/128x128@2x.png
cp master-icon.png output/server-icons/icon.png

echo "Server icons generated!"

echo ""
echo "All icons generated successfully!"
echo "Icons are in the output/ directory"
echo ""
echo "Next steps:"
echo "1. Copy ios-icons/* to both iOS Assets.xcassets/AppIcon.appiconset/ directories"
echo "2. Copy app-logos/* to both iOS Assets.xcassets/AppLogo.imageset/ and AppLogoDark.imageset/ directories"
echo "3. Copy server-icons/* to server/hostapp/src-tauri/icons/"