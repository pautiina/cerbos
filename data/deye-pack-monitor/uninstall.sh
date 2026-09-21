#!/bin/sh
set -e

SVC=/service/deye-pack-monitor
RC=/data/rc.local

if [ -e "$SVC" ]; then
    svc -d "$SVC" 2>/dev/null || true
    rm -f "$SVC"
fi

if [ -f "$RC" ]; then
    TMP="${RC}.deye.$$"
    awk '
        /# BEGIN deye-pack-monitor/ {skip=1; next}
        /# END deye-pack-monitor/   {skip=0; next}
        !skip {print}
    ' "$RC" > "$TMP"
    cat "$TMP" > "$RC"
    rm -f "$TMP"
fi

echo "Service removed from supervision/autostart."
echo "Files under /data/deye-pack-monitor were left intact."
