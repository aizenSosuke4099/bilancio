#!/bin/sh
# Compila Bilancio e la installa sull'iPhone collegato (anche per rinnovare la firma ogni 7 giorni).
# Uso: ./installa.sh   — team e iPhone vengono trovati da soli (Apple ID in Xcode › Settings › Accounts).
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | sed -n 's/.*teamID = \([A-Z0-9]*\);.*/\1/p' | head -1)
[ -n "$TEAM" ] || { echo "Nessun Apple ID in Xcode: aggiungilo da Xcode › Settings › Accounts."; exit 1; }

DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /available|connected/ && !/simulated/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }')
[ -n "$DEVICE" ] || { echo "Nessun iPhone collegato e sbloccato."; exit 1; }

echo "Compilo per l'iPhone $DEVICE (team $TEAM)…"
xcodebuild -project Bilancio.xcodeproj -scheme Bilancio -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build/device -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic COMPILER_INDEX_STORE_ENABLE=NO build -quiet

APP=build/device/Build/Products/Release-iphoneos/Bilancio.app
echo "Installo…"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" it.bilanciopersonale.app.k7x2 || \
  echo "Installata. Se non si apre: Impostazioni › Generali › VPN e gestione dispositivi › autorizza il tuo Apple ID."
