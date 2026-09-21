#!/bin/sh
#
# Deye SE-G5.1 Pro-B / LV ESS CAN diagnostic
# For Victron Cerbo GX / Venus OS / BusyBox
#
# PASSIVE SCRIPT:
#   - does NOT transmit CAN frames
#   - only captures and decodes existing CAN traffic
#
# Version: 1.1
#

VERSION="1.1"

DEFAULT_IFACE="can0"
DEFAULT_SECONDS="30"

# Maximum number of battery indexes to search.
# Deye uses sequential IDs:
#   150,151,152...
#   200,201,202...
#   500,501,502...
MAX_PACKS="${MAX_PACKS:-64}"

# Difference between system current and sum of pack currents
# before warning is generated.
# Units: 0.1 A
# 50 = 5.0 A
MISMATCH_RAW_THRESHOLD="${MISMATCH_RAW_THRESHOLD:-50}"


usage()
{
    cat <<EOF
Deye CAN diagnostic v$VERSION

Capture CAN and analyse:

  $0 [CAN_IFACE] [SECONDS] [OUTDIR]

Example:

  $0 can0 30 /tmp

Analyse an existing "candump -L" log:

  $0 --file /tmp/deye-full.log [OUTDIR]

Environment variables:

  MAX_PACKS=64
  MISMATCH_RAW_THRESHOLD=50

The script is PASSIVE.
It never transmits CAN frames.
EOF
}


have()
{
    command -v "$1" >/dev/null 2>&1
}


get_payload()
{
    _id="$1"

    grep " $_id#" "$LOG" 2>/dev/null |
        tail -n 1 |
        awk '{print $3}' |
        cut -d'#' -f2
}


get_payload_unique()
{
    _id="$1"

    grep " $_id#" "$LOG" 2>/dev/null |
        awk '{print $3}' |
        sort -u
}


byte()
{
    _hex="$1"
    _n="$2"

    _start=$(( _n * 2 + 1 ))
    _end=$(( _start + 1 ))

    echo "$_hex" | cut -c "${_start}-${_end}"
}


u16le_raw()
{
    _h="$1"
    _off="$2"

    _lo=$(byte "$_h" "$_off")
    _hi=$(byte "$_h" $(( _off + 1 )))

    if [ -z "$_lo" ] || [ -z "$_hi" ]; then
        echo 0
        return
    fi

    echo $(( 0x$_lo + (0x$_hi << 8) ))
}


s16le_raw()
{
    _v=$(u16le_raw "$1" "$2")

    if [ "$_v" -ge 32768 ]; then
        echo $(( _v - 65536 ))
    else
        echo "$_v"
    fi
}


fmt10()
{
    _v="$1"

    awk -v v="$_v" \
        'BEGIN { printf "%.1f", v / 10.0 }'
}


fmt100()
{
    _v="$1"

    awk -v v="$_v" \
        'BEGIN { printf "%.2f", v / 100.0 }'
}


fmt1000()
{
    _v="$1"

    awk -v v="$_v" \
        'BEGIN { printf "%.3f", v / 1000.0 }'
}


abs_i()
{
    _v="$1"

    if [ "$_v" -lt 0 ]; then
        echo $(( -_v ))
    else
        echo "$_v"
    fi
}


hex_ascii()
{
    #
    # Convert hex string to printable ASCII.
    # Non-printable bytes become "."
    #

    echo "$1" |
    awk '
    function nib(c, p)
    {
        p=index("0123456789ABCDEF", toupper(c))

        if (p)
            return p - 1

        return 0
    }

    function hbyte(s)
    {
        return nib(substr(s,1,1))*16 +
               nib(substr(s,2,1))
    }

    {
        for (i=1; i<=length($0); i+=2)
        {
            v=hbyte(substr($0,i,2))

            if (v >= 32 && v <= 126)
                printf "%c", v
            else
                printf "."
        }
    }'
}


id_for()
{
    _base="$1"
    _idx="$2"

    printf "%03X" $(( _base + _idx ))
}


print_line()
{
    printf '%-32s %s\n' "$1" "$2"
}


########################################################################
#
# Arguments
#
########################################################################

MODE="capture"

IFACE="$DEFAULT_IFACE"
SECONDS="$DEFAULT_SECONDS"
OUTDIR="/tmp"


if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi


if [ "$1" = "--file" ]; then

    MODE="file"

    LOG="$2"
    OUTDIR="${3:-/tmp}"

    if [ -z "$LOG" ] || [ ! -r "$LOG" ]; then
        echo "ERROR: log file is not readable: $LOG" >&2
        exit 1
    fi

else

    IFACE="${1:-$DEFAULT_IFACE}"
    SECONDS="${2:-$DEFAULT_SECONDS}"
    OUTDIR="${3:-/tmp}"

    have candump ||
    {
        echo "ERROR: candump not found" >&2
        exit 1
    }

    have ip ||
    {
        echo "ERROR: ip command not found" >&2
        exit 1
    }

    ip link show "$IFACE" >/dev/null 2>&1 ||
    {
        echo "ERROR: CAN interface $IFACE not found" >&2
        exit 1
    }

    case "$SECONDS" in
        ''|*[!0-9]*)
            echo "ERROR: SECONDS must be integer" >&2
            exit 1
            ;;
    esac

    [ -d "$OUTDIR" ] ||
        mkdir -p "$OUTDIR" ||
        exit 1

    TS=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)

    LOG="$OUTDIR/deye-can-$IFACE-$TS.log"

    LINK_BEFORE="$OUTDIR/deye-can-link-before-$TS.txt"
    LINK_AFTER="$OUTDIR/deye-can-link-after-$TS.txt"

    ip -details -statistics link show "$IFACE" \
        > "$LINK_BEFORE" 2>&1


    echo
    echo "Deye CAN diagnostic v$VERSION"
    echo
    echo "Passive capture"
    echo "Interface : $IFACE"
    echo "Duration  : ${SECONDS}s"
    echo "Raw log   : $LOG"
    echo


    candump -L "$IFACE" > "$LOG" 2>&1 &

    CAP_PID=$!


    trap '
        kill "$CAP_PID" 2>/dev/null
        wait "$CAP_PID" 2>/dev/null
    ' INT TERM EXIT


    sleep "$SECONDS"


    kill "$CAP_PID" 2>/dev/null

    wait "$CAP_PID" 2>/dev/null


    trap - INT TERM EXIT


    ip -details -statistics link show "$IFACE" \
        > "$LINK_AFTER" 2>&1

fi


########################################################################
#
# Report
#
########################################################################

REPORT="$OUTDIR/deye-can-report-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now).txt"


{

echo "============================================================"
echo " Deye CAN diagnostic v$VERSION"
echo "============================================================"

print_line "Source log:" "$LOG"

if [ "$MODE" = "capture" ]; then
    print_line "CAN interface:" "$IFACE"
fi

print_line \
    "Log lines:" \
    "$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')"


########################################################################
#
# SocketCAN state
#
########################################################################

if [ "$MODE" = "capture" ]; then

    echo
    echo "[0] SocketCAN state after capture"
    echo

    cat "$LINK_AFTER" 2>/dev/null

fi


########################################################################
#
# CAN ID inventory
#
########################################################################

echo
echo "[1] CAN IDs seen"
echo

awk '{print $3}' "$LOG" 2>/dev/null |
    grep '#' |
    cut -d'#' -f1 |
    sort |
    uniq -c


########################################################################
#
# Discover battery packs
#
########################################################################

PACKS=""
PACK_COUNT=0

i=0

while [ "$i" -lt "$MAX_PACKS" ]; do

    id500=$(id_for 0x500 "$i")
    id150=$(id_for 0x150 "$i")

    p500=$(get_payload "$id500")
    p150=$(get_payload "$id150")

    if [ -n "$p500" ] || [ -n "$p150" ]; then

        PACKS="$PACKS $i"
        PACK_COUNT=$(( PACK_COUNT + 1 ))

    fi

    i=$(( i + 1 ))

done


echo
echo "[2] Battery discovery"
echo

print_line \
    "Detected battery packs:" \
    "$PACK_COUNT"


if [ "$PACK_COUNT" -eq 0 ]; then

    echo
    echo "WARNING:"
    echo "No 0x500+n or 0x150+n battery frames detected."

fi


########################################################################
#
# Master / system
#
########################################################################

echo
echo "[3] System / master frames"
echo


P351=$(get_payload 351)
P355=$(get_payload 355)
P356=$(get_payload 356)
P35E=$(get_payload 35E)
P361=$(get_payload 361)
P363=$(get_payload 363)
P364=$(get_payload 364)


#
# 0x351
#
# CVL / CCL / DCL / low voltage
#

if [ -n "$P351" ]; then

    cvl=$(u16le_raw "$P351" 0)
    ccl=$(u16le_raw "$P351" 2)
    dcl=$(u16le_raw "$P351" 4)
    lowv=$(u16le_raw "$P351" 6)

    print_line "0x351 raw:" "$P351"

    print_line \
        "Charge voltage limit:" \
        "$(fmt10 "$cvl") V"

    print_line \
        "Charge current limit:" \
        "$(fmt10 "$ccl") A"

    print_line \
        "Discharge current limit:" \
        "$(fmt10 "$dcl") A"

    print_line \
        "Low voltage limit:" \
        "$(fmt10 "$lowv") V"

fi


#
# 0x355
#
# SOC / SOH
#

if [ -n "$P355" ]; then

    soc=$(u16le_raw "$P355" 0)
    soh=$(u16le_raw "$P355" 2)

    print_line "0x355 raw:" "$P355"

    print_line \
        "System SOC:" \
        "$soc %"

    print_line \
        "System SOH:" \
        "$soh %"

fi


#
# 0x356
#
# Voltage / current / temperature
#

SYS_CUR_RAW=""

if [ -n "$P356" ]; then

    sv=$(u16le_raw "$P356" 0)
    SYS_CUR_RAW=$(s16le_raw "$P356" 2)
    st=$(s16le_raw "$P356" 4)

    print_line "0x356 raw:" "$P356"

    print_line \
        "System voltage:" \
        "$(fmt100 "$sv") V"

    print_line \
        "System current:" \
        "$(fmt10 "$SYS_CUR_RAW") A"

    print_line \
        "System temperature:" \
        "$(fmt10 "$st") C"

fi


#
# 0x35E
#
# Manufacturer / capacity
#

if [ -n "$P35E" ]; then

    ident_hex=$(echo "$P35E" | cut -c 1-10)
    ident=$(hex_ascii "$ident_hex")

    cap=$(u16le_raw "$P35E" 6)

    print_line \
        "0x35E raw:" \
        "$P35E"

    print_line \
        "Manufacturer/ID:" \
        "$ident"

    print_line \
        "Reported capacity:" \
        "$(fmt10 "$cap") Ah"

fi


#
# 0x361
#
# System cell min/max
#

if [ -n "$P361" ]; then

    maxc=$(u16le_raw "$P361" 0)
    minc=$(u16le_raw "$P361" 2)

    maxt=$(s16le_raw "$P361" 4)
    mint=$(s16le_raw "$P361" 6)

    print_line \
        "0x361 raw:" \
        "$P361"

    print_line \
        "System max cell:" \
        "$(fmt1000 "$maxc") V"

    print_line \
        "System min cell:" \
        "$(fmt1000 "$minc") V"

    print_line \
        "System cell delta:" \
        "$(fmt1000 $(( maxc - minc ))) V"

    print_line \
        "System temperature range:" \
        "$(fmt10 "$mint") .. $(fmt10 "$maxt") C"

fi


#
# 0x363
#

if [ -n "$P363" ]; then

    print_line \
        "0x363 raw:" \
        "$P363"

    print_line \
        "0x363 SW word:" \
        "$(echo "$P363" | cut -c 1-4)"

    print_line \
        "0x363 HW/protocol word:" \
        "$(echo "$P363" | cut -c 5-8)"

fi


if [ -n "$P364" ]; then

    print_line \
        "0x364 raw/module status:" \
        "$P364"

fi


########################################################################
#
# Per battery
#
########################################################################

echo
echo "[4] Per-battery data"
echo


SUM_CUR_RAW=0

FIRST_FW=""
FIRST_HW=""

FW_MISMATCH=0
HW_MISMATCH=0

PACK_DATA_WITH_CURRENT=0

SUM_PACK_CCL=0
SUM_PACK_DCL=0

MAX_CELL_DELTA_MV=0
MAX_CELL_DELTA_PACK=0


for idx in $PACKS; do

    N=$(( idx + 1 ))


    ID110=$(id_for 0x110 "$idx")
    ID150=$(id_for 0x150 "$idx")
    ID200=$(id_for 0x200 "$idx")
    ID250=$(id_for 0x250 "$idx")
    ID400=$(id_for 0x400 "$idx")
    ID500=$(id_for 0x500 "$idx")
    ID600=$(id_for 0x600 "$idx")
    ID650=$(id_for 0x650 "$idx")


    P110=$(get_payload "$ID110")
    P150=$(get_payload "$ID150")
    P200=$(get_payload "$ID200")
    P250=$(get_payload "$ID250")
    P400=$(get_payload "$ID400")
    P500=$(get_payload "$ID500")
    P600=$(get_payload "$ID600")
    P650=$(get_payload "$ID650")


    echo "--- Battery #$N (index $idx) ---"


    ####################################################################
    # Firmware / HW
    ####################################################################

    if [ -n "$P500" ]; then

        FW=$(echo "$P500" | cut -c 1-4)
        HW=$(echo "$P500" | cut -c 5-8)

        EXTRA_HEX=$(echo "$P500" | cut -c 9-16)
        EXTRA=$(hex_ascii "$EXTRA_HEX")


        print_line \
            "$ID500 raw:" \
            "$P500"

        print_line \
            "Firmware marker:" \
            "$FW"

        print_line \
            "Hardware marker:" \
            "$HW"

        print_line \
            "Version/text field:" \
            "$EXTRA"


        if [ -z "$FIRST_FW" ]; then

            FIRST_FW="$FW"

        elif [ "$FW" != "$FIRST_FW" ]; then

            FW_MISMATCH=1

        fi


        if [ -z "$FIRST_HW" ]; then

            FIRST_HW="$HW"

        elif [ "$HW" != "$FIRST_HW" ]; then

            HW_MISMATCH=1

        fi

    else

        print_line \
            "Firmware frame:" \
            "not seen"

    fi


    ####################################################################
    # Battery ID / serial fragments
    ####################################################################

    if [ -n "$P600" ]; then

        print_line \
            "$ID600 ID part:" \
            "$(hex_ascii "$P600") ($P600)"

    fi


    if [ -n "$P650" ]; then

        print_line \
            "$ID650 ID part:" \
            "$(hex_ascii "$P650") ($P650)"

    fi


    if [ -n "$P600" ] && [ -n "$P650" ]; then

        print_line \
            "Serial/ID candidate:" \
            "$(hex_ascii "$P600")$(hex_ascii "$P650")"

    fi


    ####################################################################
    # 0x150+n
    #
    # Pack voltage / current / SOC / SOH
    ####################################################################

    if [ -n "$P150" ]; then

        pv=$(u16le_raw "$P150" 0)
        pc=$(s16le_raw "$P150" 2)

        psoc=$(u16le_raw "$P150" 4)
        psoh=$(u16le_raw "$P150" 6)


        SUM_CUR_RAW=$(( SUM_CUR_RAW + pc ))

        PACK_DATA_WITH_CURRENT=$(( PACK_DATA_WITH_CURRENT + 1 ))


        print_line \
            "$ID150 raw:" \
            "$P150"

        print_line \
            "Voltage:" \
            "$(fmt10 "$pv") V"

        print_line \
            "Current:" \
            "$(fmt10 "$pc") A"

        print_line \
            "SOC:" \
            "$(fmt10 "$psoc") %"

        print_line \
            "SOH:" \
            "$(fmt10 "$psoh") %"

    fi


    ####################################################################
    # 0x200+n
    #
    # Max/min cell + temperature
    ####################################################################

    if [ -n "$P200" ]; then

        pmax=$(u16le_raw "$P200" 0)
        pmin=$(u16le_raw "$P200" 2)

        ptmax=$(s16le_raw "$P200" 4)
        ptmin=$(s16le_raw "$P200" 6)


        pdelta=$(( pmax - pmin ))

        if [ "$pdelta" -lt 0 ]; then
            pdelta=$(( -pdelta ))
        fi


        if [ "$pdelta" -gt "$MAX_CELL_DELTA_MV" ]; then

            MAX_CELL_DELTA_MV="$pdelta"
            MAX_CELL_DELTA_PACK="$N"

        fi


        print_line \
            "$ID200 raw:" \
            "$P200"

        print_line \
            "Max cell:" \
            "$(fmt1000 "$pmax") V"

        print_line \
            "Min cell:" \
            "$(fmt1000 "$pmin") V"

        print_line \
            "Cell delta:" \
            "$(fmt1000 "$pdelta") V"

        print_line \
            "Cell temp range:" \
            "$(fmt10 "$ptmin") .. $(fmt10 "$ptmax") C"

    fi


    ####################################################################
    # 0x250+n
    #
    # MOS temperature + current limits
    ####################################################################

    if [ -n "$P250" ]; then

        mos=$(s16le_raw "$P250" 0)
        aux=$(s16le_raw "$P250" 2)

        p_ccl=$(u16le_raw "$P250" 4)
        p_dcl=$(u16le_raw "$P250" 6)


        SUM_PACK_CCL=$(( SUM_PACK_CCL + p_ccl ))
        SUM_PACK_DCL=$(( SUM_PACK_DCL + p_dcl ))


        print_line \
            "$ID250 raw:" \
            "$P250"

        print_line \
            "MOS temperature:" \
            "$(fmt10 "$mos") C"

        print_line \
            "Aux/heater temperature:" \
            "$(fmt10 "$aux") C"

        print_line \
            "Pack charge current limit:" \
            "$p_ccl A"

        print_line \
            "Pack discharge current limit:" \
            "$p_dcl A"

    fi


    ####################################################################
    # 0x110+n
    #
    # Parallel / MOS flags
    ####################################################################

    if [ -n "$P110" ]; then

        status=$(byte "$P110" 7)
        status_dec=$(( 0x$status ))

        parallel=$(( status_dec & 1 ))

        charge_mos=$(( (status_dec >> 4) & 1 ))

        discharge_mos=$(( (status_dec >> 5) & 1 ))


        print_line \
            "$ID110 raw:" \
            "$P110"

        print_line \
            "parallel_finish bit:" \
            "$parallel"

        print_line \
            "Charge MOS bit:" \
            "$charge_mos"

        print_line \
            "Discharge MOS bit:" \
            "$discharge_mos"

    fi


    ####################################################################
    # 0x400+n
    #
    # State / cycles / balancing
    ####################################################################

    if [ -n "$P400" ]; then

        mode=$(byte "$P400" 0)
        fault=$(byte "$P400" 1)

        cycles=$(u16le_raw "$P400" 2)

        balance=$(echo "$P400" | cut -c 9-12)


        print_line \
            "$ID400 raw:" \
            "$P400"

        print_line \
            "Work mode byte:" \
            "0x$mode"

        print_line \
            "Fault byte:" \
            "0x$fault"

        print_line \
            "Cycle count:" \
            "$cycles"

        print_line \
            "Balance bitmap raw:" \
            "$balance"

    fi


    echo

done


########################################################################
#
# Consistency checks
#
########################################################################

echo "[5] Consistency checks"
echo


#
# Firmware
#

if [ "$PACK_COUNT" -gt 1 ]; then

    if [ "$FW_MISMATCH" -eq 1 ]; then

        echo "WARNING: firmware markers differ between battery packs."

    else

        echo "OK: all observed battery firmware markers are identical ($FIRST_FW)."

    fi


    if [ "$HW_MISMATCH" -eq 1 ]; then

        echo "WARNING: hardware markers differ between battery packs."

    else

        echo "OK: all observed battery hardware markers are identical ($FIRST_HW)."

    fi

fi


#
# Cell imbalance
#

if [ "$MAX_CELL_DELTA_MV" -gt 100 ]; then

    echo \
    "WARNING: battery #$MAX_CELL_DELTA_PACK has a large cell delta: $(fmt1000 "$MAX_CELL_DELTA_MV") V"

elif [ "$MAX_CELL_DELTA_MV" -gt 50 ]; then

    echo \
    "NOTICE: battery #$MAX_CELL_DELTA_PACK has elevated cell delta: $(fmt1000 "$MAX_CELL_DELTA_MV") V"

elif [ "$MAX_CELL_DELTA_MV" -gt 0 ]; then

    echo \
    "OK: maximum observed per-pack cell delta: $(fmt1000 "$MAX_CELL_DELTA_MV") V (battery #$MAX_CELL_DELTA_PACK)"

fi


#
# System current versus sum of pack currents
#

if [ -n "$SYS_CUR_RAW" ] &&
   [ "$PACK_DATA_WITH_CURRENT" -gt 0 ]; then

    DIFF_RAW=$(( SYS_CUR_RAW - SUM_CUR_RAW ))

    ABS_DIFF=$(abs_i "$DIFF_RAW")


    print_line \
        "System current (0x356):" \
        "$(fmt10 "$SYS_CUR_RAW") A"

    print_line \
        "Sum of pack currents:" \
        "$(fmt10 "$SUM_CUR_RAW") A"

    print_line \
        "Difference:" \
        "$(fmt10 "$DIFF_RAW") A"


    if [ "$ABS_DIFF" -gt "$MISMATCH_RAW_THRESHOLD" ]; then

        echo
        echo "WARNING:"
        echo "System current does not match sum of individual pack currents."
        echo "Possible causes:"
        echo "  master/parallel aggregation problem"
        echo "  incompatible battery firmware"
        echo "  incompatible protocol revision"

    else

        echo \
        "OK: system current is close to sum of individual pack currents."

    fi

else

    echo \
    "INFO: insufficient frames to compare system and pack currents."

fi


#
# Sum current limits
#

if [ "$SUM_PACK_CCL" -gt 0 ] ||
   [ "$SUM_PACK_DCL" -gt 0 ]; then

    echo

    print_line \
        "Sum pack charge limits:" \
        "$SUM_PACK_CCL A"

    print_line \
        "Sum pack discharge limits:" \
        "$SUM_PACK_DCL A"

fi


#
# System capacity
#

if [ -n "$P35E" ] &&
   [ "$PACK_COUNT" -gt 0 ]; then

    cap=$(u16le_raw "$P35E" 6)

    echo

    print_line \
        "Reported system capacity:" \
        "$(fmt10 "$cap") Ah"

    print_line \
        "Detected pack count:" \
        "$PACK_COUNT"

fi


########################################################################
#
# Important raw system frames
#
########################################################################

echo
echo "[6] Raw diagnostic system frames"
echo


for id in \
    351 \
    355 \
    356 \
    359 \
    35C \
    35E \
    361 \
    363 \
    364 \
    371

do

    _u=$(get_payload_unique "$id")

    if [ -n "$_u" ]; then
        echo "$_u"
    fi

done


########################################################################
#
# Notes
#
########################################################################

echo
echo "============================================================"
echo " Diagnostic notes"
echo "============================================================"

echo
echo "Firmware markers from 0x500+n are comparison identifiers."
echo "Do not infer an official firmware filename from them."
echo

echo "The script NEVER sends CAN frames."
echo "It only captures and decodes existing traffic."
echo

echo "A mismatch warning is diagnostic evidence,"
echo "not absolute proof by itself."
echo

echo "For difficult cases compare:"
echo "  - each battery standalone"
echo "  - the same batteries in parallel"
echo

echo "============================================================"

} | tee "$REPORT"


RET=$?


echo
echo "Report saved:"
echo "  $REPORT"

echo
echo "Raw CAN log:"
echo "  $LOG"

exit "$RET"
