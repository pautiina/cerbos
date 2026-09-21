# Deye Pack Monitor for Victron Venus OS

Stable baseline: **v0.1.2**

Validated on:
- Venus OS `v3.80~53 LARGE`
- Python 3.12.14
- Deye SE-G5.1 Pro-B bank with 2 packs

## Frozen backend baseline

`deye_pack_monitor.py` v0.1.2 is the known-good backend baseline.

v0.1.2 keeps the v0.1.1 Deye CAN decoder and D-Bus model unchanged.
The only backend compatibility change is the SocketCAN / GLib watch handling:
Venus OS LARGE can report `IO_IN | IO_ERR` (`0x9`) while the CAN socket is still
readable. v0.1.2 drains readable CAN frames before treating the extra IO_ERR bit.

## Safety model

The monitor is passive:
- opens SocketCAN for receive
- never transmits CAN
- contains no CAN `send()` path
- does not replace Victron `can-bus-bms`
- deliberately does not publish `/Info/*` control paths

The stock Victron battery service therefore remains the controlling BMS for DVCC.

## Dynamic pack count

The number of physical Deye batteries is **not hard-coded**.

Default:
```sh
MAX_PACKS="64"
```

The monitor auto-discovers sequential Deye per-pack CAN IDs and creates one service
per detected physical pack.

Examples:

1 pack:
```text
com.victronenergy.battery.deyepack_can0_01
```

5 packs:
```text
com.victronenergy.battery.deyepack_can0_01
...
com.victronenergy.battery.deyepack_can0_05
```

10 packs:
```text
com.victronenergy.battery.deyepack_can0_01
...
com.victronenergy.battery.deyepack_can0_10
```

Bank diagnostics:
```text
com.victronenergy.deyebank_can0
```

## Per-pack data

Standard / common Venus paths:
- voltage/current/power
- SOC/SOH
- min/max cell voltage
- min/max cell temperature
- serial
- firmware/hardware numeric values
- charge cycles
- charged/discharged energy

Deye diagnostics:
- `/Diagnostics/Deye/FirmwareMarker`
- `/Diagnostics/Deye/HardwareMarker`
- `/Diagnostics/Deye/Revision`
- `/Diagnostics/Deye/CellDelta`
- MOS / auxiliary temperature
- pack CCL / DCL
- work mode
- fault level/text
- balancing bitmap
- charge/discharge/precharge/heater MOS
- parallel-finished state
- fault counters
- last-seen timer
- raw decoded CAN payloads

## Bank diagnostics

Includes:
- PackCount / OnlinePackCount
- firmware mismatch
- hardware mismatch
- system current
- sum of physical pack currents
- mismatch value and warning
- system SOC/SOH/capacity
- module count/status
- charge/discharge limits
- cell extrema and delta
- raw system frames

## Configuration

`/data/deye-pack-monitor/config.sh`

Defaults:
```sh
CAN_IFACE="can0"
DEVICE_INSTANCE_BASE="800"
PACK_TIMEOUT="8"
SYSTEM_TIMEOUT="8"
MAX_PACKS="64"
CURRENT_MISMATCH_THRESHOLD="5"
DEBUG="0"
```

## Installation

Extract/copy the complete directory as:

```text
/data/deye-pack-monitor
```

Then run:

```sh
/data/deye-pack-monitor/install.sh
```

The installer:
1. validates Venus Python/D-Bus dependencies;
2. creates `/service/deye-pack-monitor`;
3. adds a persistent `/data/rc.local` hook;
4. places that hook **before an existing `exit 0`**;
5. starts the supervisor service.

## Verification

```sh
svstat /service/deye-pack-monitor
dbus -y | grep -E 'deyepack|deyebank'
```

Bank:
```sh
dbus -y com.victronenergy.deyebank_can0 /Connected GetValue
dbus -y com.victronenergy.deyebank_can0 /PackCount GetValue
dbus -y com.victronenergy.deyebank_can0 /OnlinePackCount GetValue
```

Pack firmware:
```sh
dbus -y com.victronenergy.battery.deyepack_can0_02 \
  /Diagnostics/Deye/FirmwareMarker GetValue
```

Status helper:
```sh
/data/deye-pack-monitor/status.sh
```

Log:
```sh
tail -f /var/log/deye-pack-monitor/current
```

## Known validated result

On the reference 2-pack bank under Venus OS v3.80~53 LARGE:
```text
com.victronenergy.battery.deyepack_can0_01
com.victronenergy.battery.deyepack_can0_02
com.victronenergy.deyebank_can0

Connected       = 1
PackCount       = 2
OnlinePackCount = 2
```

Pack #2 firmware marker:
```text
1602
```

## Version history

### v0.1.2
- SocketCAN/GLib compatibility fix for readable condition `IO_IN|IO_ERR (0x9)`.
- Installer infrastructure fix: persistent service hook is placed before `exit 0`
  in `/data/rc.local`.
- Deye decoder and D-Bus schema unchanged from v0.1.1.

### v0.1.1
- One private D-Bus connection per exported `VeDbusService`, preventing `/`
  object-path conflicts between bank and per-pack services.

### v0.1.0
- Initial passive multi-pack monitor.

## Removal

```sh
/data/deye-pack-monitor/uninstall.sh
```

The uninstall script removes supervision/autostart but intentionally leaves the
files under `/data/deye-pack-monitor`.
