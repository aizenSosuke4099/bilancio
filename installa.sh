#!/bin/sh
# Compila Bilancio e la installa sull'iPhone collegato (anche per rinnovare la firma ogni 7 giorni).
# Uso: ./installa.sh   — team e iPhone vengono trovati da soli (Apple ID in Xcode › Settings › Accounts).
#
# Se NON sei l'autore del progetto: l'identificativo dell'app qui sotto è già registrato sul suo Apple ID e Apple
# non lo concede a un altro. Scegline uno tuo, una volta sola (resta su questo Mac, non va su GitHub):
#   echo it.iltuonome.bilancio > .identificativo
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | sed -n 's/.*teamID = \([A-Z0-9]*\);.*/\1/p' | head -1)
[ -n "$TEAM" ] || { echo "Nessun Apple ID in Xcode: aggiungilo da Xcode › Settings › Accounts."; exit 1; }

DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /available|connected/ && !/unavailable|simulated/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }')
[ -n "$DEVICE" ] || { echo "Nessun iPhone collegato e sbloccato."; exit 1; }

BUNDLE=$(cat .identificativo 2>/dev/null | tr -d '[:space:]')
[ -n "$BUNDLE" ] || BUNDLE=it.bilanciopersonale.app.k7x2

# versione nuova da GitHub (solo se non ci sono modifiche locali in sospeso)
if [ -z "$(git status --porcelain --untracked-files=no)" ]; then
  PRIMA=$(git rev-parse HEAD)
  if git pull --ff-only --quiet origin main; then
    if [ "$PRIMA" = "$(git rev-parse HEAD)" ]; then
      echo "Sei già all'ultima versione."
    else
      echo "Novità scaricate da GitHub:"
      git log --oneline "$PRIMA"..HEAD
    fi
  else
    echo "ATTENZIONE: non riesco a scaricare da GitHub (manca la rete?). Installo la versione che c'è su questo Mac."
  fi
else
  echo "Modifiche locali presenti: installo questa versione senza scaricare da GitHub."
fi
COMMIT=$(git rev-parse HEAD)

# Con l'Apple ID gratuito Xcode riusa il profilo di firma finché non scade: reinstallare non sposterebbe la scadenza.
# Si toglie quello di questa app, così Xcode ne crea uno nuovo da 7 giorni.
for f in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision "$HOME/Library/MobileDevice/Provisioning Profiles/"*.mobileprovision; do
  [ -f "$f" ] || continue
  if security cms -D -i "$f" 2>/dev/null | grep -q "\.$BUNDLE</string>"; then rm -f "$f"; fi
done

echo "Compilo per l'iPhone $DEVICE (team $TEAM, app $BUNDLE)…"
xcodebuild -project Bilancio.xcodeproj -scheme Bilancio -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build/device -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" BILANCIO_COMMIT="$COMMIT" \
  COMPILER_INDEX_STORE_ENABLE=NO build -quiet

APP=build/device/Build/Products/Release-iphoneos/Bilancio.app
echo "Installo…"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE" || \
  echo "Installata. Se non si apre: sblocca l'iPhone; la prima volta vai in Impostazioni › Generali › VPN e gestione dispositivi e autorizza il tuo Apple ID."
