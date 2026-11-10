#!/bin/bash
# Construit build/Vigie.app : une vraie app Mac autonome (Apple Silicon, arm64).
#   - rien à installer : l'app n'utilise que les bibliothèques fournies avec macOS ;
#   - signature « ad hoc » (pas de compte développeur payant → pas de notarisation).
# Usage : ./build_app.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Vigie"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="io.github.wudstyz.vigie"
MIN_MACOS="14.0"        # imposé par Package.swift (.macOS(.v14)) : API « Observation » de SwiftUI
OUT="build"
APP="$OUT/$APP_NAME.app"

echo "▶ 1/5  Compilation (release, arm64)…"
swift build -c release --arch arm64 ${SWIFTPM_FLAGS:-}
BIN="$(swift build -c release --arch arm64 ${SWIFTPM_FLAGS:-} --show-bin-path)/$APP_NAME"
[ -f "$BIN" ] || { echo "✗ binaire introuvable : $BIN"; exit 1; }

echo "▶ 2/5  Icône…"
[ -f icon/icon.icns ] || scripts/make_icns.sh

echo "▶ 3/5  Assemblage de l'app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp icon/icon.icns "$APP/Contents/Resources/icon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>fr</string>
  <key>CFBundleLocalizations</key><array><string>fr</string></array>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSRequiresAquaSystemAppearance</key><true/>
  <key>NSHumanReadableCopyright</key><string>© Wudstyz — licence MIT</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Vigie envoie un tout petit message à chaque adresse de votre réseau local pour afficher la liste des appareils connectés. Rien ne sort de votre réseau.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▶ 4/5  Signature ad hoc (binaire, puis app)…"
# Le Finder / iCloud peut poser des attributs étendus sur le dossier : codesign les refuse.
xattr -cr "$APP"
codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/$APP_NAME"
codesign --force --sign - --timestamp=none --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "▶ 5/5  Vérifications…"
ARCH="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
MINOS="$(vtool -show-build "$APP/Contents/MacOS/$APP_NAME" | awk '/minos/ {print $2; exit}')"
echo "   architecture : $ARCH"
echo "   macOS minimum (binaire) : $MINOS   (Info.plist : $MIN_MACOS)"
[ "$ARCH" = "arm64" ] || { echo "✗ architecture inattendue"; exit 1; }
[ "$MINOS" = "$MIN_MACOS" ] || { echo "✗ le macOS minimum du binaire ne correspond pas à l'Info.plist"; exit 1; }
echo "   bibliothèques liées :"
otool -L "$APP/Contents/MacOS/$APP_NAME" | tail -n +2 | awk '{print "     " $1}'
if otool -L "$APP/Contents/MacOS/$APP_NAME" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/)' ; then
  echo "✗ une dépendance hors système est liée : l'app ne serait pas autonome"; exit 1
fi
echo "   taille : $(du -sh "$APP" | awk '{print $1}')"
echo "✓ $APP prête."
