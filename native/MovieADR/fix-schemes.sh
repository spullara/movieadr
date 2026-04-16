#!/bin/bash
# Disable Metal GPU Validation and GPU Frame Capture in xcscheme files
# Run after xcodegen generate

SCHEMES_DIR="MovieADR.xcodeproj/xcshareddata/xcschemes"

for scheme in "$SCHEMES_DIR"/*.xcscheme; do
    [ -f "$scheme" ] || continue
    
    # Disable GPU Validation (replace enableGPUValidationMode="1" with "0", or add it)
    if grep -q 'enableGPUValidationMode' "$scheme"; then
        sed -i '' 's/enableGPUValidationMode = "1"/enableGPUValidationMode = "0"/g' "$scheme"
    else
        # Add to LaunchAction
        sed -i '' 's/<LaunchAction/<LaunchAction enableGPUValidationMode = "0"/g' "$scheme"
    fi
    
    # Disable GPU Frame Capture (set to 3 = disabled)
    if grep -q 'enableGPUFrameCaptureMode' "$scheme"; then
        sed -i '' 's/enableGPUFrameCaptureMode = "[0-9]*"/enableGPUFrameCaptureMode = "3"/g' "$scheme"
    else
        sed -i '' 's/enableGPUValidationMode = "0"/enableGPUValidationMode = "0" enableGPUFrameCaptureMode = "3"/g' "$scheme"
    fi
    
    echo "Patched: $scheme"
done
