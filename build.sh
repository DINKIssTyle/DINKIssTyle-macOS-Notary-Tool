#!/bin/bash

# Exit on error
set -e

APP_NAME="DKST macOS Notary"
BINARY_NAME="DKST-macOS-Notary"
BUNDLE_ID="com.dinkisstyle.notarytool"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "=== 1. Building executable target ==="
swift build -c release

echo "=== 2. Creating App Bundle Structure ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "=== 3. Copying binary ==="
cp ".build/release/$BINARY_NAME" "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"

if [ -f "Sources/Resources/Appicon.png" ]; then
    echo "=== 4. Generating AppIcon.icns ==="
    ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    
    sips -z 16 16     "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32     "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32     "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64     "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128   "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256   "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256   "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512   "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512   "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1
    sips -z 1024 1024 "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1
    
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
fi

echo "=== 5. Generating Info.plist ==="
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BINARY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

echo "=== Build Completed Successfully! ==="
echo "App Bundle created at: $APP_BUNDLE"
