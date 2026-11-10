#!/bin/bash
# Test MANUEL de la vigilance : provoque une vraie anomalie pour vérifier que Vigie la détecte.
#
# Le programme de test est volontairement « louche » :
#   • il est NON SIGNÉ et lancé depuis un dossier temporaire ;
#   • il ouvre le port TCP 48650 sur toutes les interfaces (visible depuis le réseau local) ;
#   • il ENVOIE ~45 Mo vers le serveur public de test de débit de Cloudflare (speed.cloudflare.com),
#     c'est-à-dire que ces ~45 Mo sortent réellement de votre Mac (et passent par votre connexion).
# Il ne fait rien d'autre et s'arrête seul au bout d'environ 2 minutes.
#
# Usage : lancez Vigie (mode réel, vigilance activée, apprentissage de 15 min terminé),
#         puis dans le Terminal :   tests/anomaly/run.sh
# Résultat attendu dans Vigie > Vigilance : « agent-test envoie beaucoup de données sur Internet »,
#         « agent-test accepte des connexions venant du réseau (port 48650) »,
#         « agent-test tourne depuis un dossier inhabituel », « Nouvelle application : agent-test ».
set -euo pipefail
cd "$(dirname "$0")"
read -r -p "Ceci enverra ~45 Mo vers speed.cloudflare.com. Continuer ? [o/N] " rep
[ "${rep:-N}" = "o" ] || [ "${rep:-N}" = "O" ] || { echo "Annulé."; exit 0; }
WORK="$(mktemp -d /tmp/vigie-anomalie.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
swiftc -O agent-test.swift -o "$WORK/agent-test"
echo "▶ Lancement de agent-test (≈ 2 min). Regardez l'onglet Vigilance de Vigie…"
"$WORK/agent-test"
