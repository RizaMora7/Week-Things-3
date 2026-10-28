#!/bin/bash
# Builds «Semana» (weekly view for Things 3) without an Xcode project.
# MacBook Air 2017 / macOS 13 / Swift 5.8 / SDK 13.3
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Semana"
BUNDLE_ID="cl.zamorano.semana"
BUILD_DIR="$HERE/build"
APP="$BUILD_DIR/$APP_NAME.app"
TARGET="x86_64-apple-macosx13.0"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

echo "→ Building $APP_NAME (swiftc, $TARGET)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Measured on this machine: -O (whole-module) takes minutes; without -O it compiles and links
# in ~24 s. That's why the default build doesn't optimise. OPTIMIZE=1 for the optimised binary.

ARGS=(-sdk "$SDK" -target "$TARGET"
      -framework AppKit -framework ServiceManagement -lsqlite3
      -o "$APP/Contents/MacOS/$APP_NAME")
[ -n "${OPTIMIZE:-}" ] && ARGS+=(-O)

swiftc "${ARGS[@]}" "$HERE"/Sources/*.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.6</string>
    <key>CFBundleVersion</key><string>7</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key><string>Vista semanal de solo lectura para Things 3.</string>
</dict>
</plist>
PLIST

if [ -f "$HERE/Resources/AppIcon.icns" ]; then
  cp "$HERE/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Signing identity. Ad-hoc ("-") is enough to run locally, but the hash changes
# on every build and macOS asks for Full Disk Access again. With a stable
# identity (your own "Code Signing" certificate or Apple Development) the permission
# sticks:  SIGN_ID="Semana Dev" ./build.sh
SIGN_ID="${SIGN_ID:--}"
echo "→ Signing with identity: ${SIGN_ID}  ('-' = ad-hoc)"
codesign --force --deep --sign "$SIGN_ID" "$APP" >/dev/null 2>&1 \
  || codesign --force --sign "$SIGN_ID" "$APP"

# Optional install to a fixed path (TCC also keys on the .app's location).
if [ -n "${INSTALL_DIR:-}" ]; then
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
  cp -R "$APP" "$INSTALL_DIR/"
  echo "→ Installed at: $INSTALL_DIR/$APP_NAME.app"
fi

echo "→ Done: $APP"
echo "  Try it:  open '$APP'"
