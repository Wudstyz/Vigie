#!/bin/bash
# Test de fumée : lance l'app construite dans un bac à sable qui INTERDIT l'accès à Homebrew et /usr/local
# (simule un Mac neuf), en mode démonstration, et vérifie que les 9 écrans se dessinent (captures PNG).
# Usage : ./build_app.sh && tests/smoke_test.sh [dossier_de_sortie]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Vigie.app/Contents/MacOS/Vigie"
[ -x "$APP" ] || { echo "✗ lancez d'abord ./build_app.sh"; exit 1; }
OUT="${1:-$(mktemp -d)}"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "▶ Lancement dans le bac à sable (sans Homebrew)… ~40 s"
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  sandbox-exec -f tests/sandbox_no_homebrew.sb "$APP" --capture "$OUT" >/dev/null 2>&1 &
PID=$!
for i in $(seq 1 90); do kill -0 $PID 2>/dev/null || break; sleep 1; done
kill $PID 2>/dev/null || true

N=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "   captures produites : $N / 9  (dans $OUT)"
[ "$N" = "9" ] || { echo "✗ échec"; exit 1; }
echo "✓ L'app démarre et dessine tous ses écrans sans Homebrew."
