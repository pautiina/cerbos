#!/bin/sh
set -e

APP=/data/deye-pack-monitor
SVC=/service/deye-pack-monitor

if [ ! -f "$APP/deye_pack_monitor.py" ]; then
    echo "ERROR: install.sh must be run from an installed copy at $APP" >&2
    echo "Copy this directory to $APP first." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 not found" >&2
    exit 1
fi

if ! command -v dbus >/dev/null 2>&1; then
    echo "WARNING: dbus CLI not found; monitor itself may still work"
fi

python3 - <<'PY'
import os, sys
for p in (
    "/opt/victronenergy/dbus-systemcalc-py/ext/velib_python",
    "/opt/victronenergy/velib_python",
):
    if os.path.isdir(p):
        sys.path.insert(1, p)
import dbus
from gi.repository import GLib
from vedbus import VeDbusService
print("Venus D-Bus Python dependencies: OK")
PY

chmod +x "$APP/deye_pack_monitor.py" "$APP/install.sh" "$APP/uninstall.sh" "$APP/status.sh" \
         "$APP/service/run" "$APP/service/log/run"

rm -f "$SVC"
ln -s "$APP/service" "$SVC"

RC=/data/rc.local
if [ ! -f "$RC" ]; then
    echo '#!/bin/sh' > "$RC"
fi
chmod +x "$RC"

if ! grep -q 'BEGIN deye-pack-monitor' "$RC" 2>/dev/null; then
    cat >> "$RC" <<'EOF'

# BEGIN deye-pack-monitor
if [ -d /data/deye-pack-monitor/service ] && [ ! -e /service/deye-pack-monitor ]; then
    ln -s /data/deye-pack-monitor/service /service/deye-pack-monitor
fi
# END deye-pack-monitor
EOF
fi

svc -u "$SVC" 2>/dev/null || true
sleep 1
svstat "$SVC" 2>/dev/null || true

echo
echo "Installed. Monitor is passive and never transmits CAN frames."
echo "Logs: /var/log/deye-pack-monitor/current"
echo "Status: $APP/status.sh"
