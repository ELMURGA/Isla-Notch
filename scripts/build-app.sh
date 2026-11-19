#!/bin/sh
# Compila Isla y la empaqueta como Isla.app (firma local, sin cuenta de desarrollador).
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Isla.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Isla "$APP/Contents/MacOS/Isla"
cp Resources/*.svg "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Isla</string>
  <key>CFBundleDisplayName</key><string>Isla</string>
  <key>CFBundleIdentifier</key><string>com.dazenty.isla</string>
  <key>CFBundleExecutable</key><string>Isla</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Isla enseña tu próxima reunión en el notch y te avisa 10 minutos antes.</string>
  <key>NSAppleEventsUsageDescription</key><string>Isla muestra la canción que suena en Spotify o Apple Music y te deja pausarla o cambiarla desde el notch.</string>
</dict>
</plist>
PLIST
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Listo: $(pwd)/$APP"
