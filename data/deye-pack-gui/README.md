# Deye Pack GUI v0.5.1

Remote GUI-v2 integration for the passive **Deye Pack Monitor** backend.

This release is functionally the same as v0.5.0.  
v0.5.1 is a documentation/packaging update with a complete installation,
upgrade, verification and troubleshooting guide.

---

## 1. What this project does

`deye-pack-gui` is a GUI-only layer for Victron Venus OS.

It reads the D-Bus/MQTT data exported by:

```text
deye-pack-monitor v0.1.2
```

and displays:

- Deye battery bank summary
- total/online physical pack count
- SOC / voltage / current / power
- current aggregation mismatch
- cell min/max/delta
- charge/discharge limits
- firmware/hardware mismatch
- dynamic list of physical Deye battery packs
- per-pack firmware/revision/serial
- per-pack electrical data
- temperatures
- MOS state
- parallel state
- history and fault counters

The GUI does **not** access CAN directly and does not control the BMS.

---

## 2. Backend requirement

The supported backend baseline is:

```text
deye-pack-monitor v0.1.2
```

The backend is intentionally frozen separately from the GUI.

Expected services:

```text
com.victronenergy.deyebank_can0

com.victronenergy.battery.deyepack_can0_01
com.victronenergy.battery.deyepack_can0_02
...
```

The number of physical batteries is dynamic.

Examples supported without GUI changes:

```text
1 pack
2 packs
5 packs
7 packs
10 packs
...
```

The backend default limit is:

```text
MAX_PACKS=64
```

---

## 3. Tested environment

Confirmed working reference environment:

```text
Venus OS:      v3.80~53 LARGE
GUI-v2:        v1.3.22
Backend:       deye-pack-monitor v0.1.2
Access mode:   Remote GUI-v2 / WASM
Transport:     MQTT
```

A local HDMI/GX display is **not required** for Remote Console use.

Venus OS **LARGE** is recommended when compiling the plugin directly on the GX
device because the plugin compiler requires Qt tools such as:

```text
lupdate
lrelease
/usr/libexec/rcc
```

Check:

```sh
command -v lupdate
command -v lrelease
ls -l /usr/libexec/rcc
```

---

## 4. Verify the backend before installing the GUI

Check supervisor:

```sh
svstat /service/deye-pack-monitor
```

Expected:

```text
/service/deye-pack-monitor: up ...
```

Check exported D-Bus services:

```sh
dbus -y | grep -E 'deyepack|deyebank'
```

Example for two packs:

```text
com.victronenergy.battery.deyepack_can0_01
com.victronenergy.battery.deyepack_can0_02
com.victronenergy.deyebank_can0
```

Check bank status:

```sh
dbus -y com.victronenergy.deyebank_can0 /Connected GetValue
dbus -y com.victronenergy.deyebank_can0 /PackCount GetValue
dbus -y com.victronenergy.deyebank_can0 /OnlinePackCount GetValue
```

Example:

```text
1
2
2
```

---

## 5. Installation

Copy:

```text
deye-pack-gui-v0.5.1.tar.gz
```

to the GX device, for example:

```text
/data/deye-pack-gui-v0.5.1.tar.gz
```

Create the application directories if they do not already exist:

```sh
mkdir -p /data/apps/available
mkdir -p /data/apps/enabled
```

Remove an older GUI package:

```sh
rm -f /data/apps/enabled/deye-pack-gui
rm -rf /data/apps/available/deye-pack-gui
```

Extract:

```sh
cd /data/apps/available
tar -xzf /data/deye-pack-gui-v0.5.1.tar.gz
```

Make the installer executable:

```sh
chmod +x /data/apps/available/deye-pack-gui/install.sh
```

Install/compile:

```sh
/data/apps/available/deye-pack-gui/install.sh
```

A successful build should include:

```text
--- running lupdate
--- running lrelease
--- writing .qrc
--- running rcc
--- base64 encoding rcc data
--- building integrations dictionary
--- writing compiled json
--- done!
```

The resulting compiled manifest is:

```text
/data/apps/available/deye-pack-gui/gui-v2/deye-pack-gui.json
```

The enabled application should be a symlink:

```text
/data/apps/enabled/deye-pack-gui
    -> /data/apps/available/deye-pack-gui
```

Verify:

```sh
ls -la /data/apps/available/deye-pack-gui/gui-v2
ls -la /data/apps/enabled/deye-pack-gui
```

---

## 6. Open the GUI remotely

After installation, reload Remote Console / New UI.

Recommended browser refresh:

```text
Ctrl+Shift+R
```

Open:

```text
Settings
  -> Integrations
     -> deye-pack-gui
```

The main page contains:

```text
Connected
Pack count
Online packs
SOC
Voltage
System current
Current mismatch
Cell delta
Firmware mismatch

Battery packs
Electrical & limits
Cells & temperatures
System & firmware
```

---

## 7. Dynamic pack discovery

The GUI does not assume a fixed number of batteries.

It reads:

```text
com.victronenergy.system /Batteries
```

and keeps only service IDs beginning with:

```text
com.victronenergy.battery.deyepack_
```

For each pack, the GUI builds a portable service UID using:

```qml
BackendConnection.serviceUidFromName(b.id, b.instance)
```

This works with both local D-Bus and Remote/WASM MQTT backends.

Example:

```text
D-Bus:
com.victronenergy.battery.deyepack_can0_02

DeviceInstance:
801

Remote GUI UID:
mqtt/battery/801
```

---

## 8. Per-pack pages

Open:

```text
Deye Battery Bank
  -> Battery packs
     -> Deye Pack #N
```

The pack summary shows:

```text
Connected
Firmware version
FW marker
HW marker
SOC
Voltage
Current
Cell delta
Fault
```

Additional pages:

```text
Identification
Electrical & cells
BMS status
History & faults
```

---

## 9. Firmware display

Do not use the standard Victron numeric:

```text
/FirmwareVersion
```

as the human-readable Deye firmware version.

The GUI intentionally uses:

```text
/Diagnostics/Deye/Revision
```

for the user-facing firmware version.

Examples:

```text
Pack #1:
Firmware version   7.06
FW marker          200A
HW marker          AA56

Pack #2:
Firmware version   1.10
FW marker          1602
HW marker          AA56
```

The marker and revision are kept separate because they describe different
pieces of information observed in Deye CAN frames.

---

## 10. Diagnostic warning thresholds

The GUI currently uses presentation/monitoring thresholds:

```text
Current mismatch > 5 A
    -> WARNING

Cell delta > 100 mV
    -> WARNING
```

These are project diagnostic thresholds.

They are **not** claimed to be official Deye factory protection limits.

---

## 11. Remote GUI / MQTT transport

Remote GUI-v2/WASM receives the plugin through MQTT.

The plugin is exported by the GX device through:

```text
GuiCustomizations
```

To verify:

```sh
VRMID="$(dbus -y com.victronenergy.system /Serial GetValue | tr -d "'")"

mosquitto_sub \
    -h 127.0.0.1 \
    -t "N/$VRMID/GuiCustomizations/#" \
    -v
```

The list should contain:

```text
deye-pack-gui
```

The compiled plugin may be split into multiple MQTT chunks.

This is normal.

---

## 12. Verify per-pack MQTT data

Example for DeviceInstance 801:

```sh
VRMID="$(dbus -y com.victronenergy.system /Serial GetValue | tr -d "'")"

mosquitto_sub \
    -h 127.0.0.1 \
    -t "N/$VRMID/battery/801/#" \
    -v
```

Useful paths include:

```text
Soc
Dc/0/Voltage
Dc/0/Current

Serial

Diagnostics/Deye/FirmwareMarker
Diagnostics/Deye/HardwareMarker
Diagnostics/Deye/Revision
Diagnostics/Deye/CellDelta
Diagnostics/Deye/MosTemperature
Diagnostics/Deye/ChargeCurrentLimit
Diagnostics/Deye/DischargeCurrentLimit
Diagnostics/Deye/ParallelFinished
Diagnostics/Deye/ChargeMos
Diagnostics/Deye/DischargeMos
Diagnostics/Deye/FaultLevelText
```

---

## 13. Updating the GUI

The backend does not need to be stopped.

To replace only the GUI:

```sh
rm -f /data/apps/enabled/deye-pack-gui
rm -rf /data/apps/available/deye-pack-gui

cd /data/apps/available
tar -xzf /data/deye-pack-gui-v0.5.1.tar.gz

chmod +x /data/apps/available/deye-pack-gui/install.sh
/data/apps/available/deye-pack-gui/install.sh
```

Then hard-refresh the browser:

```text
Ctrl+Shift+R
```

The GUI update does **not** modify:

```text
/data/deye-pack-monitor
/service/deye-pack-monitor
```

---

## 14. Disable / uninstall the GUI

Disable:

```sh
rm -f /data/apps/enabled/deye-pack-gui
```

or run:

```sh
/data/apps/available/deye-pack-gui/uninstall.sh
```

Then reload Remote GUI.

The backend continues to run.

If you also want to remove the GUI files:

```sh
rm -rf /data/apps/available/deye-pack-gui
```

Do not remove `/data/deye-pack-monitor` unless you intentionally want to remove
the backend as well.

---

## 15. Recovery if a GUI page breaks navigation

A malformed plugin page can cause GUI-v2 navigation to stop responding after
the page fails to load.

Recovery:

```sh
rm -f /data/apps/enabled/deye-pack-gui
```

Then hard-refresh the browser:

```text
Ctrl+Shift+R
```

This disables only the GUI integration.

It does not affect the Deye monitor or CAN.

Browser developer console is useful for QML errors.

A previous compatibility issue on GUI-v2 v1.3.22 was:

```text
ListSectionHeader is not a type
```

For that reason this project currently avoids `ListSectionHeader` and uses
components already tested with this GUI-v2 release.

---

## 16. After a Venus OS firmware update

The important persistent files are under:

```text
/data/deye-pack-monitor
/data/apps/available/deye-pack-gui
/data/apps/enabled/deye-pack-gui
```

After upgrading Venus OS, verify:

```sh
svstat /service/deye-pack-monitor
dbus -y | grep -E 'deyepack|deyebank'
```

and verify the GUI symlink:

```sh
ls -la /data/apps/enabled/deye-pack-gui
```

If the GUI compiler/API changed in the new Venus release, rebuild the plugin by
running:

```sh
/data/apps/available/deye-pack-gui/install.sh
```

If the backend service symlink is missing, use the backend's own installer or
restore its supervisor link. Do not modify the GUI to repair the backend.

---

## 17. Backend safety model

The backend `deye-pack-monitor v0.1.2` is passive.

It:

- listens to SocketCAN
- decodes Deye PCS CAN frames
- exports read-only diagnostic D-Bus services
- has no CAN transmit path
- does not replace the stock Victron CAN-BMS service
- does not publish `/Info/*` control paths

The stock service remains the controlling BMS:

```text
com.victronenergy.battery.socketcan_can0
```

The Deye physical pack services are diagnostic/monitoring services.

---

## 18. Known current limitation

The plugin is installed under:

```text
Settings -> Integrations
```

The currently tested Plugin API does not provide this project with a stable,
supported way to add its own custom card directly to the main Overview screen.

For now the v0.5.x branch intentionally stays inside the supported Integration
page hierarchy.

---

## 19. Project version matrix

```text
Backend:
deye-pack-monitor v0.1.2
    Stable/frozen baseline

GUI:
deye-pack-gui v0.5.1
    Structured Remote GUI-v2 interface
    Dynamic physical pack discovery
```

Recommended pairing:

```text
deye-pack-monitor v0.1.2
+
deye-pack-gui v0.5.x
```

---

## 20. Quick health check

Backend:

```sh
svstat /service/deye-pack-monitor
```

Services:

```sh
dbus -y | grep -E 'deyepack|deyebank'
```

Bank:

```sh
dbus -y com.victronenergy.deyebank_can0 / GetValue
```

Pack example:

```sh
dbus -y com.victronenergy.battery.deyepack_can0_02 / GetValue
```

GUI:

```sh
ls -la /data/apps/enabled/deye-pack-gui
ls -la /data/apps/available/deye-pack-gui/gui-v2
```

If all of these are present, the complete Deye monitor + Remote GUI stack is
normally ready.
