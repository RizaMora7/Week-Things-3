#!/bin/bash
# Construye «Semana» (vista semanal de Things 3) sin proyecto de Xcode.
# MacBook Air 2017 / macOS 13 / Swift 5.8 / SDK 13.3
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Semana"
BUNDLE_ID="cl.zamorano.semana"
BUILD_DIR="$HERE/build"
APP="$BUILD_DIR/$APP_NAME.app"
TARGET="x86_64-apple-macosx13.0"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

echo "→ Compilando $APP_NAME (swiftc, $TARGET)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Medido en esta máquina: -O (whole-module) tarda minutos; sin -O compila y enlaza
# en ~24 s. Por eso el build por defecto no optimiza. OPTIMIZE=1 para el binario fino.

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

# Identidad de firma. Ad-hoc ("-") basta para correr en local, pero cambia el hash
# en cada build y macOS vuelve a pedir Acceso Total al Disco. Con una identidad
# estable (certificado propio de "Code Signing" o Apple Development) el permiso
# queda fijo:  SIGN_ID="Semana Dev" ./build.sh
SIGN_ID="${SIGN_ID:--}"
echo "→ Firmando con identidad: ${SIGN_ID}  ('-' = ad-hoc)"
codesign --force --deep --sign "$SIGN_ID" "$APP" >/dev/null 2>&1 \
  || codesign --force --sign "$SIGN_ID" "$APP"

# Instalación opcional en ruta fija (TCC también clavea por ubicación del .app).
if [ -n "${INSTALL_DIR:-}" ]; then
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
  cp -R "$APP" "$INSTALL_DIR/"
  echo "→ Instalada en: $INSTALL_DIR/$APP_NAME.app"
fi

echo "→ Listo: $APP"
echo "  Prueba:  open '$APP'"
