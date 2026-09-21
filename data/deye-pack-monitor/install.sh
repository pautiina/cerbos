#!/bin/sh
set -e

APP=/data/deye-pack-monitor
SVC=/service/deye-pack-monitor
RC=/data/rc.local

if [ ! -f "$APP/deye_pack_monitor.py" ]; then
    echo "ERROR: install.sh must be run from an installed copy at $APP" >&2
    echo "Copy/extract this directory to $APP first." >&2
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

chmod +x "$APP/deye_pack_monitor.py" "$APP/deye_protocol.py" \
         "$APP/install.sh" "$APP/uninstall.sh" "$APP/status.sh" \
         "$APP/service/run" "$APP/service/log/run"

# Supervisor service is runtime state and can disappear after Venus firmware update.
rm -f "$SVC"
ln -s "$APP/service" "$SVC"

# Persistent boot hook.
if [ ! -f "$RC" ]; then
    printf '%s\n' '#!/bin/sh' > "$RC"
fi
chmod +x "$RC"

# Remove any old Deye block first, even if an earlier installer placed it
# after "exit 0".
TMP1="${RC}.deye.clean.$$"
TMP2="${RC}.deye.new.$$"

awk '
    /# BEGIN deye-pack-monitor/ {skip=1; next}
    /# END deye-pack-monitor/   {skip=0; next}
    !skip {print}
' "$RC" > "$TMP1"

# Insert the hook before the first top-level "exit 0". If no such line exists,
# append the hook at EOF.
if grep -Eq '^[[:space:]]*exit[[:space:]]+0[[:space:]]*$' "$TMP1"; then
    awk '
        BEGIN {inserted=0}
        !inserted && /^[[:space:]]*exit[[:space:]]+0[[:space:]]*$/ {
            print ""
            print "# BEGIN deye-pack-monitor"
            print "if [ -d /data/deye-pack-monitor/service ] && [ ! -e /service/deye-pack-monitor ]; then"
            print "    ln -s /data/deye-pack-monitor/service /service/deye-pack-monitor"
            print "fi"
            print "# END deye-pack-monitor"
            print ""
            inserted=1
        }
        {print}
    ' "$TMP1" > "$TMP2"
else
    cat "$TMP1" > "$TMP2"
    cat >> "$TMP2" <<'EOF'

# BEGIN deye-pack-monitor
if [ -d /data/deye-pack-monitor/service ] && [ ! -e /service/deye-pack-monitor ]; then
    ln -s /data/deye-pack-monitor/service /service/deye-pack-monitor
fi
# END deye-pack-monitor
EOF
fi

cat "$TMP2" > "$RC"
rm -f "$TMP1" "$TMP2"
chmod +x "$RC"

svc -u "$SVC" 2>/dev/null || true
sleep 1
svstat "$SVC" 2>/dev/null || true

echo
echo "Installed Deye Pack Monitor v0.1.2."
echo "Passive monitor: no CAN transmit path exists."
echo "Logs:   /var/log/deye-pack-monitor/current"
echo "Status: $APP/status.sh"
