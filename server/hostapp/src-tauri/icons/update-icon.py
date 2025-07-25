#!/usr/bin/env python3
"""
Script to update Tauri app icons
Place your new icon file in this directory and run:
python3 update-icon.py your-icon-file.png
"""

import sys
import os
import subprocess

def generate_icons(source_file):
    """Generate all required icon sizes from source file"""
    
    if not os.path.exists(source_file):
        print(f"Error: Source file '{source_file}' not found")
        return False
    
    sizes = [
        (512, 512, "icon.png"),
        (256, 256, "128x128@2x.png"),
        (128, 128, "128x128.png"),
        (32, 32, "32x32.png")
    ]
    
    print(f"Generating icons from {source_file}...")
    
    for width, height, output in sizes:
        cmd = ["sips", "-z", str(height), str(width), source_file, "--out", output]
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"Error generating {output}: {result.stderr}")
            return False
        else:
            print(f"✓ Generated {output} ({width}x{height})")
    
    return True

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 update-icon.py <source-icon-file>")
        print("Source icon should be at least 512x512 pixels")
        sys.exit(1)
    
    source = sys.argv[1]
    
    if generate_icons(source):
        print("\nIcon generation complete!")
        print("The Tauri app will use the new icons on next build.")
    else:
        print("\nIcon generation failed!")
        sys.exit(1)