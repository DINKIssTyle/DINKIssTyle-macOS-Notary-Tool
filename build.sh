#!/bin/bash

# Exit on error
set -e

APP_NAME="DKST macOS Notary"
BINARY_NAME="DKST-macOS-Notary"
BUNDLE_ID="com.dinkisstyle.notarytool"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ICON_FILE="AppIcon"
DNT_ICON_FILE="DNTDocument"

echo "=== 1. Building executable target ==="
swift build -c release --disable-sandbox -debug-info-format none

echo "=== 2. Creating App Bundle Structure ==="
if [ -d "$APP_BUNDLE" ]; then
    chmod -R u+w "$APP_BUNDLE"
fi
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

if [ -f "THIRD_PARTY_NOTICES.md" ]; then
    cp "THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.md"
fi

TEMPLATE_RESOURCES_DIR="$APP_BUNDLE/Contents/Resources/Templates"
mkdir -p "$TEMPLATE_RESOURCES_DIR"
for TEMPLATE_FILE in "Templates/DMG-BG-TEMP0.psd" "Templates/DMG-BG-TEMP1.psd" "Templates/DMG-BG-TEMP2.psd" "Templates/PKG-Installer-BG-TEMP.psd"; do
    if [ -f "$TEMPLATE_FILE" ]; then
        cp "$TEMPLATE_FILE" "$TEMPLATE_RESOURCES_DIR/"
    fi
done
chmod 0444 "$TEMPLATE_RESOURCES_DIR"/*.psd
chmod 0555 "$TEMPLATE_RESOURCES_DIR"

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
    # Force a resample so a 16-bit 1024px source becomes the 8-bit PNG that
    # iconutil expects for the largest iconset member.
    sips -z 1023 1023 "Sources/Resources/Appicon.png" --out "$ICONSET_DIR/.icon_1023.png" >/dev/null 2>&1
    sips -z 1024 1024 "$ICONSET_DIR/.icon_1023.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1
    rm -f "$ICONSET_DIR/.icon_1023.png"
    xattr -cr "$ICONSET_DIR"
    
    if ! iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"; then
        echo "iconutil rejected the iconset; using the source PNG as the bundle icon."
        cp "Sources/Resources/Appicon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
        ICON_FILE="AppIcon.png"
    fi
    rm -rf "$ICONSET_DIR"
fi

if [ -f "Sources/Resources/dnt.png" ]; then
    echo "=== 4b. Generating DNTDocument.icns ==="
    DNT_ICONSET_DIR="$BUILD_DIR/DNTDocument.iconset"
    rm -rf "$DNT_ICONSET_DIR"
    mkdir -p "$DNT_ICONSET_DIR"

    sips -z 16 16     "Sources/Resources/dnt.png" --out "$DNT_ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32     "Sources/Resources/dnt.png" --out "$DNT_ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32     "Sources/Resources/dnt.png" --out "$DNT_ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64     "Sources/Resources/dnt.png" --out "$DNT_ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128   "Sources/Resources/dnt.png" --out "$DNT_ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256   "Sources/Resources/dnt.png" --out "$DNT_ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256   "Sources/Resources/dnt.png" --out "$DNT_ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512   "Sources/Resources/dnt.png" --out "$DNT_ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512   "Sources/Resources/dnt.png" --out "$DNT_ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1
    sips -z 1023 1023 "Sources/Resources/dnt.png" --out "$DNT_ICONSET_DIR/.icon_1023.png" >/dev/null 2>&1
    sips -z 1024 1024 "$DNT_ICONSET_DIR/.icon_1023.png" --out "$DNT_ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1
    rm -f "$DNT_ICONSET_DIR/.icon_1023.png"
    xattr -cr "$DNT_ICONSET_DIR"

    if ! iconutil -c icns "$DNT_ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/DNTDocument.icns"; then
        echo "iconutil rejected the DNT iconset; using the source PNG as the document icon."
        cp "Sources/Resources/dnt.png" "$APP_BUNDLE/Contents/Resources/DNTDocument.png"
        DNT_ICON_FILE="DNTDocument.png"
    fi
    rm -rf "$DNT_ICONSET_DIR"
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
    <key>NSHumanReadableCopyright</key>
    <string>Copyright (C) 2026 DINKI'ssTyle. All rights reserved.</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_FILE</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>DKST Notary Project</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSTypeIsPackage</key>
            <true/>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.dinkisstyle.notarytool.dnt-project</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>dnt</string>
            </array>
            <key>CFBundleTypeIconFile</key>
            <string>$DNT_ICON_FILE</string>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.dinkisstyle.notarytool.dnt-project</string>
            <key>UTTypeDescription</key>
            <string>DKST Notary Project</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>com.apple.package</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>dnt</string>
                </array>
            </dict>
            <key>UTTypeIconFile</key>
            <string>$DNT_ICON_FILE</string>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "=== Build Completed Successfully! ==="
echo "App Bundle created at: $APP_BUNDLE"
