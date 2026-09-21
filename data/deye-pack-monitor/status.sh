#!/bin/sh
APP=/data/deye-pack-monitor
[ -r "$APP/config.sh" ] && . "$APP/config.sh"
CAN_IFACE=${CAN_IFACE:-can0}
SAFE_IFACE=$(echo "$CAN_IFACE" | sed 's/[^A-Za-z0-9_]/_/g')
BANK="com.victronenergy.deyebank_${SAFE_IFACE}"

echo "=== supervisor ==="
svstat /service/deye-pack-monitor 2>/dev/null || echo "service not installed"
echo
echo "=== bank diagnostics ==="
dbus -y "$BANK" / GetValue 2>/dev/null || echo "$BANK not present yet"
echo
echo "=== recent log ==="
tail -n 30 /var/log/deye-pack-monitor/current 2>/dev/null || true
