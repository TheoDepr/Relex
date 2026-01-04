#!/bin/bash

# Build script for building Relex

set -e

echo "🏗️  Building Relex"

# Clean previous builds
xcodebuild clean -project Relex.xcodeproj -scheme Relex -configuration Release

# Build Release version
xcodebuild -project Relex.xcodeproj \
  -scheme Relex \
  -configuration Release \
  -derivedDataPath ./build \
  build

APP_PATH="./build/Build/Products/Release/Relex.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed - app not found"
    exit 1
fi

echo "✅ Build successful!"
echo "📦 App location: $APP_PATH"

# Sign with ad-hoc signature (better than nothing)
echo "🔏 Applying ad-hoc signature..."
codesign --force --deep --sign - "$APP_PATH"

# Create distributable ZIP
echo "📦 Creating distribution package..."
DIST_DIR="./dist"
mkdir -p "$DIST_DIR"
ZIP_NAME="Relex-macOS.zip"

cd ./build/Build/Products/Release
zip -r "../../../../$DIST_DIR/$ZIP_NAME" Relex.app
cd ../../../../

echo "✅ Distribution package created: $DIST_DIR/$ZIP_NAME"
echo ""
echo "📋 Installation instructions for users:"
echo "1. Download and unzip Relex-macOS.zip"
echo "2. Move Relex.app to Applications folder"
echo "3. Right-click Relex.app and select 'Open' (first time only)"
echo "4. Click 'Open' in the security dialog"
echo "5. Grant Accessibility and Microphone permissions"
echo ""
echo "⚠️  Note: Users will see a security warning because the app is not notarized."
echo "   They must right-click > Open (not double-click) the first time."
