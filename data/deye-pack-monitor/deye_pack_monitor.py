#!/usr/bin/env python3
"""Passive Deye per-pack monitor for Victron Venus OS.

- Listens to an existing SocketCAN interface.
- NEVER transmits a CAN frame.
- Creates one read-only com.victronenergy.battery.* service per Deye pack.
- Creates one com.victronenergy.deyebank_* diagnostic service for bank checks.
- Intentionally does NOT publish /Info/* BMS-control paths, so it cannot act as
  the DVCC controlling BMS.
"""

from __future__ import annotations

import argparse
import logging
import os
import platform
import re
import socket
import struct
import sys
import time
from typing import Dict, Optional

VERSION = "0.1.2"
PRODUCT_ID = 0xFFFF

# Venus OS ships velib_python here. Keep a couple of fallbacks for variants.
for _p in (
    "/opt/victronenergy/dbus-systemcalc-py/ext/velib_python",
    "/opt/victronenergy/velib_python",
    os.path.join(os.path.dirname(__file__), "ext", "velib_python"),
):
    if os.path.isdir(_p) and _p not in sys.path:
        sys.path.insert(1, _p)

try:
    import dbus  # type: ignore
    from dbus.mainloop.glib import DBusGMainLoop  # type: ignore
    from gi.repository import GLib  # type: ignore
    from vedbus import VeDbusService  # type: ignore
except Exception as exc:  # pragma: no cover - only meaningful on Venus OS
    sys.stderr.write("Unable to import Venus OS D-Bus libraries: %s\n" % (exc,))
    sys.stderr.write("Expected vedbus.py under /opt/victronenergy/dbus-systemcalc-py/ext/velib_python\n")
    raise

from deye_protocol import (  # noqa: E402
    SYSTEM_IDS,
    decode_pack_frame,
    decode_system_frame,
    identify_pack_frame,
)

LOG = logging.getLogger("deye-pack-monitor")

CAN_EFF_FLAG = 0x80000000
CAN_RTR_FLAG = 0x40000000
CAN_ERR_FLAG = 0x20000000
CAN_SFF_MASK = 0x000007FF
CAN_FRAME = struct.Struct("=IB3x8s")


def sanitize_name(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9_]", "_", value)
    if not value or not value[0].isalpha():
        value = "can_" + value
    return value


class SystemBus(dbus.bus.BusConnection):
    """Create a *new* private connection to the system bus.

    dbus.SystemBus() is shared/cached by dbus-python.  VeDbusService exports a
    root object at '/', therefore multiple VeDbusService instances cannot share
    the same connection: their root object handlers would collide.
    """

    def __new__(cls):
        return dbus.bus.BusConnection.__new__(
            cls, dbus.bus.BusConnection.TYPE_SYSTEM
        )


class SessionBus(dbus.bus.BusConnection):
    """Create a *new* private connection to the session bus."""

    def __new__(cls):
        return dbus.bus.BusConnection.__new__(
            cls, dbus.bus.BusConnection.TYPE_SESSION
        )


def dbusconnection():
    """Return a fresh D-Bus connection for one VeDbusService."""
    return SessionBus() if 'DBUS_SESSION_BUS_ADDRESS' in os.environ else SystemBus()


def _fmt_fw(marker: Optional[str]) -> str:
    return marker or "unknown"


def _marker_int(marker: Optional[str]) -> int:
    try:
        return int(marker or "0", 16)
    except ValueError:
        return 0


class PackService:
    LIVE_PATHS = (
        "/Dc/0/Voltage",
        "/Dc/0/Current",
        "/Dc/0/Power",
        "/Dc/0/Temperature",
        "/Soc",
        "/Soh",
        "/System/MaxCellVoltage",
        "/System/MinCellVoltage",
        "/System/MaxCellTemperature",
        "/System/MinCellTemperature",
        "/Diagnostics/Deye/CellDelta",
        "/Diagnostics/Deye/MosTemperature",
        "/Diagnostics/Deye/AuxTemperature",
        "/Diagnostics/Deye/ChargeCurrentLimit",
        "/Diagnostics/Deye/DischargeCurrentLimit",
    )

    RAW_PATHS = {
        "status": "/Diagnostics/Deye/Raw/Frame110",
        "telemetry": "/Diagnostics/Deye/Raw/Frame150",
        "cell_extrema": "/Diagnostics/Deye/Raw/Frame200",
        "limits": "/Diagnostics/Deye/Raw/Frame250",
        "state": "/Diagnostics/Deye/Raw/Frame400",
        "identity": "/Diagnostics/Deye/Raw/Frame500",
        "energy": "/Diagnostics/Deye/Raw/Frame550",
        "serial_a": "/Diagnostics/Deye/Raw/Frame600",
        "serial_b": "/Diagnostics/Deye/Raw/Frame650",
        "fault_history_a": "/Diagnostics/Deye/Raw/Frame700",
        "fault_history_b": "/Diagnostics/Deye/Raw/Frame750",
    }

    def __init__(self, iface: str, index: int, device_instance: int, timeout_s: float):
        self.iface = iface
        self.index = index
        self.number = index + 1
        self.timeout_s = timeout_s
        self.last_seen = time.monotonic()
        self.serial_a = ""
        self.serial_b = ""
        self.fw_marker: Optional[str] = None
        self.hw_marker: Optional[str] = None
        self.revision_text = ""
        self.online = True
        self.update_index = 0

        suffix = sanitize_name(iface)
        self.service_name = "com.victronenergy.battery.deyepack_%s_%02d" % (suffix, self.number)
        self.s = VeDbusService(self.service_name, bus=dbusconnection(), register=False)

        self.s.add_path("/Mgmt/ProcessName", __file__)
        self.s.add_path("/Mgmt/ProcessVersion", VERSION + " / Python " + platform.python_version())
        self.s.add_path("/Mgmt/Connection", "Passive Deye PCS CAN monitor on %s" % iface)
        self.s.add_path("/DeviceInstance", device_instance)
        self.s.add_path("/ProductId", PRODUCT_ID)
        self.s.add_path("/ProductName", "Deye SE-G5.1 Pro-B Pack #%d" % self.number)
        self.s.add_path("/CustomName", "Deye Pack #%d" % self.number)
        self.s.add_path("/Manufacturer", "Deye")
        self.s.add_path("/Connected", 1)
        self.s.add_path("/Serial", "")
        self.s.add_path("/FirmwareVersion", 0, gettextcallback=self._fw_gettext)
        self.s.add_path("/HardwareVersion", 0, gettextcallback=self._hw_gettext)
        self.s.add_path("/UpdateIndex", 0)

        # Standard battery measurements that Venus GUI/systemcalc understands.
        for path in (
            "/Dc/0/Voltage", "/Dc/0/Current", "/Dc/0/Power", "/Dc/0/Temperature",
            "/Soc", "/Soh", "/System/MaxCellVoltage", "/System/MinCellVoltage",
            "/System/MaxCellTemperature", "/System/MinCellTemperature",
            "/History/ChargeCycles", "/History/ChargedEnergy", "/History/DischargedEnergy",
        ):
            self.s.add_path(path, None)

        # Deye-specific diagnostics. These are read-only on purpose.
        diag_paths = {
            "/Diagnostics/Deye/PackIndex": index,
            "/Diagnostics/Deye/FirmwareMarker": "",
            "/Diagnostics/Deye/HardwareMarker": "",
            "/Diagnostics/Deye/Revision": "",
            "/Diagnostics/Deye/CellDelta": None,
            "/Diagnostics/Deye/MosTemperature": None,
            "/Diagnostics/Deye/AuxTemperature": None,
            "/Diagnostics/Deye/ChargeCurrentLimit": None,
            "/Diagnostics/Deye/DischargeCurrentLimit": None,
            "/Diagnostics/Deye/Cycles": None,
            "/Diagnostics/Deye/WorkMode": None,
            "/Diagnostics/Deye/WorkModeText": "",
            "/Diagnostics/Deye/FaultLevel": None,
            "/Diagnostics/Deye/FaultLevelText": "",
            "/Diagnostics/Deye/BalanceBitmap": None,
            "/Diagnostics/Deye/ParallelFinished": None,
            "/Diagnostics/Deye/ChargeMos": None,
            "/Diagnostics/Deye/DischargeMos": None,
            "/Diagnostics/Deye/PrechargeMos": None,
            "/Diagnostics/Deye/HeatMos": None,
            "/Diagnostics/Deye/LastSeenSeconds": 0.0,
            "/Diagnostics/Deye/FaultCount/ChargeOverVoltage": None,
            "/Diagnostics/Deye/FaultCount/DischargeUnderVoltage": None,
            "/Diagnostics/Deye/FaultCount/ShortCircuit": None,
            "/Diagnostics/Deye/FaultCount/MosOverTemperature": None,
            "/Diagnostics/Deye/FaultCount/ChargeOverCurrent": None,
            "/Diagnostics/Deye/FaultCount/DischargeOverCurrent": None,
            "/Diagnostics/Deye/FaultCount/ChargeOverTemperature": None,
            "/Diagnostics/Deye/FaultCount/DischargeOverTemperature": None,
        }
        for path, value in diag_paths.items():
            self.s.add_path(path, value)
        for path in self.RAW_PATHS.values():
            self.s.add_path(path, "")

        self.s.register()
        LOG.info("Created %s DeviceInstance=%d", self.service_name, device_instance)

    def _fw_gettext(self, path, value):
        return _fmt_fw(self.fw_marker)

    def _hw_gettext(self, path, value):
        return _fmt_fw(self.hw_marker)

    def _bump(self):
        self.update_index = (self.update_index + 1) % 256
        self.s["/UpdateIndex"] = self.update_index

    def _set(self, path: str, value):
        self.s[path] = value

    def seen(self):
        self.last_seen = time.monotonic()
        if not self.online:
            LOG.info("Pack #%d is online again", self.number)
        self.online = True
        self._set("/Connected", 1)
        self._set("/Diagnostics/Deye/LastSeenSeconds", 0.0)

    def update_frame(self, kind: str, data: bytes):
        self.seen()
        decoded = decode_pack_frame(kind, data)
        raw_path = self.RAW_PATHS.get(kind)
        if raw_path:
            self._set(raw_path, decoded.get("raw", ""))

        if kind == "telemetry":
            self._set("/Dc/0/Voltage", decoded["voltage"])
            self._set("/Dc/0/Current", decoded["current"])
            self._set("/Dc/0/Power", decoded["power"])
            self._set("/Soc", decoded["soc"])
            self._set("/Soh", decoded["soh"])

        elif kind == "cell_extrema":
            self._set("/System/MaxCellVoltage", decoded["max_cell_voltage"])
            self._set("/System/MinCellVoltage", decoded["min_cell_voltage"])
            self._set("/System/MaxCellTemperature", decoded["max_cell_temperature"])
            self._set("/System/MinCellTemperature", decoded["min_cell_temperature"])
            self._set("/Dc/0/Temperature", decoded["max_cell_temperature"])
            self._set("/Diagnostics/Deye/CellDelta", decoded["cell_delta"])

        elif kind == "limits":
            self._set("/Diagnostics/Deye/MosTemperature", decoded["mos_temperature"])
            self._set("/Diagnostics/Deye/AuxTemperature", decoded["aux_temperature"])
            self._set("/Diagnostics/Deye/ChargeCurrentLimit", decoded["charge_current_limit"])
            self._set("/Diagnostics/Deye/DischargeCurrentLimit", decoded["discharge_current_limit"])

        elif kind == "status":
            self._set("/Diagnostics/Deye/ParallelFinished", decoded["parallel_finished"])
            self._set("/Diagnostics/Deye/ChargeMos", decoded["charge_mos"])
            self._set("/Diagnostics/Deye/DischargeMos", decoded["discharge_mos"])
            self._set("/Diagnostics/Deye/PrechargeMos", decoded["precharge_mos"])
            self._set("/Diagnostics/Deye/HeatMos", decoded["heat_mos"])

        elif kind == "state":
            self._set("/History/ChargeCycles", decoded["cycles"])
            self._set("/Diagnostics/Deye/Cycles", decoded["cycles"])
            self._set("/Diagnostics/Deye/WorkMode", decoded["work_mode"])
            self._set("/Diagnostics/Deye/WorkModeText", decoded["work_mode_text"])
            self._set("/Diagnostics/Deye/FaultLevel", decoded["fault_level"])
            self._set("/Diagnostics/Deye/FaultLevelText", decoded["fault_level_text"])
            self._set("/Diagnostics/Deye/BalanceBitmap", decoded["balance_bitmap"])

        elif kind == "identity":
            self.fw_marker = str(decoded["firmware_marker"])
            self.hw_marker = str(decoded["hardware_marker"])
            self.revision_text = str(decoded["revision_text"])
            self._set("/FirmwareVersion", _marker_int(self.fw_marker))
            self._set("/HardwareVersion", _marker_int(self.hw_marker))
            self._set("/Diagnostics/Deye/FirmwareMarker", self.fw_marker)
            self._set("/Diagnostics/Deye/HardwareMarker", self.hw_marker)
            self._set("/Diagnostics/Deye/Revision", self.revision_text)

        elif kind == "serial_a":
            self.serial_a = str(decoded["serial_a"])
            self._update_serial()

        elif kind == "serial_b":
            self.serial_b = str(decoded["serial_b"])
            self._update_serial()

        elif kind == "energy":
            self._set("/History/ChargedEnergy", decoded["charged_energy"])
            self._set("/History/DischargedEnergy", decoded["discharged_energy"])

        elif kind == "fault_history_a":
            self._set("/Diagnostics/Deye/FaultCount/ChargeOverVoltage", decoded["charge_over_voltage_count"])
            self._set("/Diagnostics/Deye/FaultCount/DischargeUnderVoltage", decoded["discharge_under_voltage_count"])
            self._set("/Diagnostics/Deye/FaultCount/ShortCircuit", decoded["short_circuit_count"])
            self._set("/Diagnostics/Deye/FaultCount/MosOverTemperature", decoded["mos_over_temperature_count"])

        elif kind == "fault_history_b":
            self._set("/Diagnostics/Deye/FaultCount/ChargeOverCurrent", decoded["charge_over_current_count"])
            self._set("/Diagnostics/Deye/FaultCount/DischargeOverCurrent", decoded["discharge_over_current_count"])
            self._set("/Diagnostics/Deye/FaultCount/ChargeOverTemperature", decoded["charge_over_temperature_count"])
            self._set("/Diagnostics/Deye/FaultCount/DischargeOverTemperature", decoded["discharge_over_temperature_count"])

        self._bump()

    def _update_serial(self):
        serial = (self.serial_a + self.serial_b).strip()
        if serial:
            self._set("/Serial", serial)

    def periodic(self, now: float):
        age = max(0.0, now - self.last_seen)
        self._set("/Diagnostics/Deye/LastSeenSeconds", round(age, 1))
        if age > self.timeout_s and self.online:
            self.online = False
            self._set("/Connected", 0)
            for path in self.LIVE_PATHS:
                self._set(path, None)
            LOG.warning("Pack #%d offline (no frames for %.1fs)", self.number, age)

    def current(self) -> Optional[float]:
        try:
            value = self.s["/Dc/0/Current"]
            return None if value is None else float(value)
        except Exception:
            return None


class BankService:
    def __init__(self, iface: str, mismatch_threshold: float):
        suffix = sanitize_name(iface)
        self.service_name = "com.victronenergy.deyebank_%s" % suffix
        self.s = VeDbusService(self.service_name, bus=dbusconnection(), register=False)
        self.last_system_seen = 0.0
        self.system_current: Optional[float] = None
        self.mismatch_threshold = mismatch_threshold
        self.update_index = 0

        self.s.add_path("/Mgmt/ProcessName", __file__)
        self.s.add_path("/Mgmt/ProcessVersion", VERSION + " / Python " + platform.python_version())
        self.s.add_path("/Mgmt/Connection", "Passive Deye bank diagnostics on %s" % iface)
        self.s.add_path("/DeviceInstance", 0)
        self.s.add_path("/ProductId", PRODUCT_ID)
        self.s.add_path("/ProductName", "Deye Battery Bank Diagnostics")
        self.s.add_path("/CustomName", "Deye Bank Diagnostics")
        self.s.add_path("/Connected", 0)
        self.s.add_path("/UpdateIndex", 0)

        paths = {
            "/PackCount": 0,
            "/OnlinePackCount": 0,
            "/FirmwareMismatch": 0,
            "/HardwareMismatch": 0,
            "/System/Voltage": None,
            "/System/Current": None,
            "/System/Power": None,
            "/System/Temperature": None,
            "/System/Soc": None,
            "/System/Soh": None,
            "/System/CapacityAh": None,
            "/System/ManufacturerId": "",
            "/System/CellManufacturer": "",
            "/System/MaxCellVoltage": None,
            "/System/MinCellVoltage": None,
            "/System/CellDelta": None,
            "/System/MaxCellTemperature": None,
            "/System/MinCellTemperature": None,
            "/System/MaxChargeVoltage": None,
            "/System/MaxChargeCurrent": None,
            "/System/MaxDischargeCurrent": None,
            "/System/BatteryLowVoltage": None,
            "/System/ArrayChargeCurrentLimit": None,
            "/System/ArrayDischargeCurrentLimit": None,
            "/System/SoftwareWord": "",
            "/System/HardwareProtocolWord": "",
            "/System/ModulesNormal": None,
            "/System/ModulesChargeDisabled": None,
            "/System/ModulesDischargeDisabled": None,
            "/System/ModulesCommunicationDisconnected": None,
            "/System/ModulesTotal": None,
            "/System/ChargingAllowed": None,
            "/System/DischargingAllowed": None,
            "/System/AlarmsRaw": "",
            "/PackCurrentSum": None,
            "/CurrentMismatch": None,
            "/CurrentMismatchAbs": None,
            "/CurrentMismatchWarning": 0,
            "/LastSystemSeenSeconds": None,
        }
        for path, value in paths.items():
            self.s.add_path(path, value)
        for cid in sorted(SYSTEM_IDS):
            self.s.add_path("/Raw/Frame%03X" % cid, "")
        self.s.register()
        LOG.info("Created %s", self.service_name)

    def _set(self, path: str, value):
        self.s[path] = value

    def _bump(self):
        self.update_index = (self.update_index + 1) % 256
        self.s["/UpdateIndex"] = self.update_index

    def update_system_frame(self, can_id: int, data: bytes):
        self.last_system_seen = time.monotonic()
        self._set("/Connected", 1)
        d = decode_system_frame(can_id, data)
        self._set("/Raw/Frame%03X" % can_id, d.get("raw", ""))

        mapping = {
            0x351: {
                "max_charge_voltage": "/System/MaxChargeVoltage",
                "max_charge_current": "/System/MaxChargeCurrent",
                "max_discharge_current": "/System/MaxDischargeCurrent",
                "battery_low_voltage": "/System/BatteryLowVoltage",
            },
            0x355: {"soc": "/System/Soc", "soh": "/System/Soh"},
            0x356: {
                "voltage": "/System/Voltage", "current": "/System/Current",
                "power": "/System/Power", "temperature": "/System/Temperature",
            },
            0x35E: {
                "capacity_ah": "/System/CapacityAh", "manufacturer_id": "/System/ManufacturerId",
                "cell_manufacturer": "/System/CellManufacturer",
            },
            0x361: {
                "max_cell_voltage": "/System/MaxCellVoltage", "min_cell_voltage": "/System/MinCellVoltage",
                "cell_delta": "/System/CellDelta", "max_cell_temperature": "/System/MaxCellTemperature",
                "min_cell_temperature": "/System/MinCellTemperature",
            },
            0x363: {
                "software_word": "/System/SoftwareWord",
                "hardware_protocol_word": "/System/HardwareProtocolWord",
            },
            0x364: {
                "modules_normal": "/System/ModulesNormal",
                "modules_charge_disabled": "/System/ModulesChargeDisabled",
                "modules_discharge_disabled": "/System/ModulesDischargeDisabled",
                "modules_communication_disconnected": "/System/ModulesCommunicationDisconnected",
                "modules_total": "/System/ModulesTotal",
            },
            0x371: {
                "array_charge_current_limit": "/System/ArrayChargeCurrentLimit",
                "array_discharge_current_limit": "/System/ArrayDischargeCurrentLimit",
            },
            0x35C: {
                "charging_allowed": "/System/ChargingAllowed",
                "discharging_allowed": "/System/DischargingAllowed",
            },
        }
        if can_id == 0x356:
            self.system_current = float(d["current"])
        if can_id == 0x359:
            self._set("/System/AlarmsRaw", d.get("alarm_bytes", ""))
        for key, path in mapping.get(can_id, {}).items():
            if key in d:
                self._set(path, d[key])
        self._bump()

    def periodic(self, packs: Dict[int, PackService], now: float, timeout_s: float):
        all_packs = list(packs.values())
        online = [p for p in all_packs if p.online]
        self._set("/PackCount", len(all_packs))
        self._set("/OnlinePackCount", len(online))

        fw = {p.fw_marker for p in online if p.fw_marker}
        hw = {p.hw_marker for p in online if p.hw_marker}
        self._set("/FirmwareMismatch", 1 if len(fw) > 1 else 0)
        self._set("/HardwareMismatch", 1 if len(hw) > 1 else 0)

        currents = [p.current() for p in online]
        valid_currents = [x for x in currents if x is not None]
        if valid_currents:
            total = sum(valid_currents)
            self._set("/PackCurrentSum", total)
            if self.system_current is not None:
                mismatch = self.system_current - total
                self._set("/CurrentMismatch", mismatch)
                self._set("/CurrentMismatchAbs", abs(mismatch))
                self._set("/CurrentMismatchWarning", 1 if abs(mismatch) > self.mismatch_threshold else 0)
        else:
            self._set("/PackCurrentSum", None)
            self._set("/CurrentMismatch", None)
            self._set("/CurrentMismatchAbs", None)
            self._set("/CurrentMismatchWarning", 0)

        if self.last_system_seen:
            age = max(0.0, now - self.last_system_seen)
            self._set("/LastSystemSeenSeconds", round(age, 1))
            if age > timeout_s:
                self._set("/Connected", 0)
        self._bump()


class Monitor:
    def __init__(self, args):
        self.args = args
        self.packs: Dict[int, PackService] = {}
        self.bank = BankService(args.interface, args.current_mismatch_threshold)
        self.sock = socket.socket(socket.PF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
        self.sock.bind((args.interface,))
        self.sock.setblocking(False)
        self.watch_id = GLib.io_add_watch(
            self.sock.fileno(),
            GLib.IO_IN | GLib.IO_ERR | GLib.IO_HUP,
            self._on_can_ready,
        )
        GLib.timeout_add_seconds(1, self._periodic)
        LOG.info("Listening passively on %s; no CAN transmit path exists in this program", args.interface)

    def _ensure_pack(self, index: int) -> PackService:
        pack = self.packs.get(index)
        if pack is None:
            pack = PackService(
                self.args.interface,
                index,
                self.args.instance_base + index,
                self.args.pack_timeout,
            )
            self.packs[index] = pack
        return pack

    def _on_can_ready(self, source, condition):
        """Drain readable CAN frames even when GLib also reports IO_ERR.

        Venus OS LARGE / newer GLib may report SocketCAN readiness as
        IO_IN|IO_ERR (0x9).  The socket is still readable in that state.
        Treating IO_ERR as fatal before recv() causes a busy loop and drops
        all CAN frames, so IO_IN always takes precedence here.
        """
        cond = int(condition)
        nval = getattr(GLib, "IO_NVAL", 0)
        fatal_mask = GLib.IO_HUP | nval

        # If there is no readable data, only then handle pure error/fatal states.
        if not (condition & GLib.IO_IN):
            if condition & fatal_mask:
                LOG.error("SocketCAN watch reported fatal condition 0x%x", cond)
                return False
            if condition & GLib.IO_ERR:
                try:
                    err = self.sock.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
                except OSError as exc:
                    LOG.warning("SocketCAN SO_ERROR query failed: %s", exc)
                    err = 0
                if err:
                    LOG.warning(
                        "SocketCAN watch reported IO_ERR 0x%x, SO_ERROR=%d (%s)",
                        cond,
                        err,
                        os.strerror(err),
                    )
            return True

        # IO_IN wins: drain all available CAN frames first.
        while True:
            try:
                frame = self.sock.recv(CAN_FRAME.size)
            except BlockingIOError:
                break
            except OSError as exc:
                LOG.exception("SocketCAN recv failed: %s", exc)
                break

            if len(frame) != CAN_FRAME.size:
                continue

            can_id_raw, dlc, payload = CAN_FRAME.unpack(frame)

            # Ignore extended/RTR/error CAN frames; this monitor only consumes
            # normal 11-bit Deye data frames.
            if can_id_raw & (CAN_EFF_FLAG | CAN_RTR_FLAG | CAN_ERR_FLAG):
                continue

            can_id = can_id_raw & CAN_SFF_MASK
            data = payload[: min(dlc, 8)]

            if can_id in SYSTEM_IDS:
                self.bank.update_system_frame(can_id, data)

            ident = identify_pack_frame(can_id, self.args.max_packs)
            if ident is not None:
                idx, kind = ident
                self._ensure_pack(idx).update_frame(kind, data)

        # A simultaneous IO_ERR on SocketCAN is non-fatal when frames were
        # readable.  Check SO_ERROR, but do not discard valid traffic.
        if condition & GLib.IO_ERR:
            try:
                err = self.sock.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
            except OSError:
                err = 0
            if err:
                LOG.warning(
                    "SocketCAN readable with IO_ERR 0x%x, SO_ERROR=%d (%s)",
                    cond,
                    err,
                    os.strerror(err),
                )

        # HUP/NVAL after draining is treated as fatal so supervisor can restart
        # the process rather than leaving a dead watch installed.
        if condition & fatal_mask:
            LOG.error("SocketCAN watch reported fatal condition 0x%x after recv", cond)
            return False

        return True

    def _periodic(self):
        now = time.monotonic()
        for pack in self.packs.values():
            pack.periodic(now)
        self.bank.periodic(self.packs, now, self.args.system_timeout)
        return True


def parse_args():
    p = argparse.ArgumentParser(description="Passive Deye per-pack D-Bus monitor for Venus OS")
    p.add_argument("--interface", default="can0")
    p.add_argument("--instance-base", type=int, default=800)
    p.add_argument("--pack-timeout", type=float, default=8.0)
    p.add_argument("--system-timeout", type=float, default=8.0)
    p.add_argument("--max-packs", type=int, default=64)
    p.add_argument("--current-mismatch-threshold", type=float, default=5.0)
    p.add_argument("--debug", action="store_true")
    return p.parse_args()


def main():
    args = parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    DBusGMainLoop(set_as_default=True)
    LOG.info("Starting v%s", VERSION)
    LOG.info("Per-pack DeviceInstance range starts at %d", args.instance_base)
    Monitor(args)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
