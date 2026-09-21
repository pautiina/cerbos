#!/bin/sh
set -eu

APP="deye-pack-gui"
DIR="/data/apps/available/$APP"
ENABLED="/data/apps/enabled/$APP"
COMPILER="/opt/victronenergy/gui-v2/gui-v2-plugin-compiler.py"

echo "Deye Pack GUI v0.5.1 installer"

if [ ! -f "$COMPILER" ]; then
    echo "ERROR: GUI-v2 plugin compiler not found: $COMPILER" >&2
    exit 1
fi

if [ ! -f "$DIR/DeyeBank_PageSettings.qml" ]; then
    echo "ERROR: missing $DIR/DeyeBank_PageSettings.qml" >&2
    exit 1
fi

mkdir -p /data/apps/available /data/apps/enabled "$DIR/gui-v2"

cd "$DIR"
rm -f "$APP.json"

python3 "$COMPILER" \
    --name "$APP" \
    --version "0.5.1" \
    --min-required-version "v1.3.22" \
    --settings DeyeBank_PageSettings.qml

test -f "$APP.json"
mv -f "$APP.json" "$DIR/gui-v2/$APP.json"

rm -f "$ENABLED"
ln -s "$DIR" "$ENABLED"

echo
echo "Installed Deye Pack GUI v0.5.1."
echo "Hard-refresh Remote Console."
echo "Open: Settings -> Integrations -> deye-pack-gui"
