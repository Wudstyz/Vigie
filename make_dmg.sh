#!/bin/bash
# Fabrique build/Vigie-<version>.dmg (avec raccourci vers « Applications ») et sa somme SHA-256.
# Usage : ./make_dmg.sh   (lance d'abord ./build_app.sh si l'app n'existe pas)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Vigie"
VERSION="${VERSION:-1.0}"
APP="build/$APP_NAME.app"
DMG="build/$APP_NAME-$VERSION.dmg"

[ -d "$APP" ] || ./build_app.sh

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Première ouverture.txt" <<'TXT'
VIGIE — première ouverture

1. Glissez « Vigie » dans le dossier « Applications ».
2. Vigie n'est pas signée par un compte développeur payant : au premier lancement,
   faites un CLIC DROIT sur Vigie > « Ouvrir » > « Ouvrir ».
   (Ou, dans le Terminal :  xattr -dr com.apple.quarantine /Applications/Vigie.app )
3. Tout ce qui s'affiche est lu en direct sur votre Mac. Aucun mot de passe n'est demandé,
   sauf si vous activez le « mode avancé » (noms de domaine).
4. Pour essayer sans rien exposer : activez « Mode démonstration » en bas de la barre latérale.
TXT

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
( cd build && shasum -a 256 "$APP_NAME-$VERSION.dmg" > "$APP_NAME-$VERSION.dmg.sha256" )
echo "✓ $DMG ($(du -h "$DMG" | awk '{print $1}'))"
cat "build/$APP_NAME-$VERSION.dmg.sha256"
