# Deye Pack Monitor for Victron Venus OS

Version 0.1.0.

A passive companion service for Deye SE-G5.1 Pro-B / compatible Deye LV ESS batteries connected to a Victron GX device over SocketCAN.

## Safety model

The program **never transmits CAN frames**. There is no `send()` call and no CAN TX path in the program. It only opens a CAN RAW socket and receives existing traffic.

It does **not** replace Victron `can-bus-bms` and deliberately does **not** publish `/Info/*` BMS control paths. The existing system BMS therefore remains the controlling battery for DVCC.

## What it creates

For each detected physical Deye pack:

`com.victronenergy.battery.deyepack_can0_01`

`com.victronenergy.battery.deyepack_can0_02`

...and so on.

A bank diagnostic service is also created:

`com.victronenergy.deyebank_can0`

Pack discovery is dynamic; the number of batteries is not hard-coded.

## Data per pack

Standard Venus battery paths:

- Voltage, current and calculated power
- SOC / SOH
- Min/max cell voltage
- Min/max temperature
- Serial number
- Firmware / hardware marker
- Charge cycles
- Charged / discharged energy

Deye-specific diagnostic paths include:

- firmware marker, hardware marker, revision text
- cell delta
- MOS and auxiliary/heater temperature
- pack charge/discharge current limits
- work mode and fault level
- balancing bitmap
- charge/discharge/precharge/heater MOS states
- parallel-finished state
- historical fault counters
- last-seen timer
- raw CAN payload for every decoded per-pack frame

## Bank diagnostics

The bank service includes system CAN data and comparisons:

- detected / online pack count
- firmware mismatch
- hardware mismatch
- system current
- sum of individual pack currents
- current mismatch + warning
- system SOC/SOH/capacity
- module count and communication status from 0x364
- limits and cell extrema
- raw system frames

## Installation

Copy the whole directory to the GX device:

```sh
scp -r deye-pack-monitor root@CERBO:/data/
```

Then:

```sh
ssh root@CERBO
/data/deye-pack-monitor/install.sh
```

Check:

```sh
/data/deye-pack-monitor/status.sh
```

or:

```sh
svstat /service/deye-pack-monitor
tail -f /var/log/deye-pack-monitor/current
```

## Configuration

Edit `/data/deye-pack-monitor/config.sh`.

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

Restart after changes:

```sh
svc -t /service/deye-pack-monitor
```

## Useful D-Bus commands

Whole second battery:

```sh
dbus -y com.victronenergy.battery.deyepack_can0_02 / GetValue
```

Exact firmware marker:

```sh
dbus -y com.victronenergy.battery.deyepack_can0_02 /Diagnostics/Deye/FirmwareMarker GetValue
```

Serial:

```sh
dbus -y com.victronenergy.battery.deyepack_can0_02 /Serial GetValue
```

Bank diagnostics:

```sh
dbus -y com.victronenergy.deyebank_can0 / GetValue
```

## Notes about firmware/hardware fields

The standard `/FirmwareVersion` and `/HardwareVersion` D-Bus values are numeric because that is the Victron API convention. Their `GetText` form returns the Deye marker. The exact marker is also available as a string under `/Diagnostics/Deye/FirmwareMarker` and `/Diagnostics/Deye/HardwareMarker`.

Example:

```sh
dbus -y com.victronenergy.battery.deyepack_can0_01 /FirmwareVersion GetText
```

## Removal

```sh
/data/deye-pack-monitor/uninstall.sh
```

The files in `/data/deye-pack-monitor` are intentionally left in place.


## v0.1.1

Fix: use one private D-Bus connection per exported VeDbusService. This avoids root object-path conflicts when the bank service and multiple per-pack services coexist in the same Python process.
