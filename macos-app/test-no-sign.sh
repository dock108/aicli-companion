#!/bin/bash
# Run tests without code signing
# This is fastest for local development

cd "$(dirname "$0")"

echo "🧪 Running tests without code signing..."

xcodebuild test \
    -project AICLICompanionHost.xcodeproj \
    -scheme AICLICompanionHost \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    2>&1 | xcbeautify --renderer terminal || true

echo "✅ Tests complete"