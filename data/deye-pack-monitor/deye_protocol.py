#!/usr/bin/env python3
"""Pure protocol helpers for Deye SE-G5.1 Pro-B / LV ESS PCS CAN.

No D-Bus and no SocketCAN dependencies.  This module is deliberately kept
small so decoding can be unit-tested away from Venus OS.
"""

from __future__ import annotations

from typing import Dict, Optional, Tuple

PACK_FRAME_BASES = {
    "status": 0x110,
    "telemetry": 0x150,
    "cell_extrema": 0x200,
    "limits": 0x250,
    "state": 0x400,
    "identity": 0x500,
    "energy": 0x550,
    "serial_a": 0x600,
    "serial_b": 0x650,
    "fault_history_a": 0x700,
    "fault_history_b": 0x750,
}

SYSTEM_IDS = {0x351, 0x355, 0x356, 0x359, 0x35C, 0x35E, 0x361, 0x363, 0x364, 0x371}

CELL_MANUFACTURERS = {
    1: "GOTION 96Ah",
    2: "CATL 100Ah",
    3: "EVE 100Ah",
    4: "PH 100Ah",
    5: "EVE 120Ah",
    6: "PH 100Ah(214R)",
    7: "ZENERGY 104Ah",
}


def u16le(data: bytes, offset: int = 0) -> int:
    return data[offset] | (data[offset + 1] << 8)


def s16le(data: bytes, offset: int = 0) -> int:
    value = u16le(data, offset)
    return value - 0x10000 if value & 0x8000 else value


def u32le(data: bytes, offset: int = 0) -> int:
    return (
        data[offset]
        | (data[offset + 1] << 8)
        | (data[offset + 2] << 16)
        | (data[offset + 3] << 24)
    )


def ascii_field(data: bytes) -> str:
    # Deye identity fields are simple printable ASCII.  Preserve internal
    # spaces, strip NUL/0xff padding at the ends.
    chars = []
    for b in data:
        if 32 <= b <= 126:
            chars.append(chr(b))
        elif b in (0x00, 0xFF):
            chars.append("\x00")
        else:
            chars.append(".")
    return "".join(chars).strip("\x00 ")


def hex_marker(data: bytes) -> str:
    return data.hex().upper()


def identify_pack_frame(can_id: int, max_packs: int = 64) -> Optional[Tuple[int, str]]:
    """Return (zero-based pack index, frame kind), or None.

    Deye enumerates packs by incrementing the base CAN id: pack 1 uses the
    base, pack 2 base+1, etc.  64 is intentionally conservative and can be
    raised from the monitor config if a future model uses more.
    """
    for kind, base in PACK_FRAME_BASES.items():
        idx = can_id - base
        if 0 <= idx < max_packs:
            return idx, kind
    return None


def decode_pack_frame(kind: str, data: bytes) -> Dict[str, object]:
    if len(data) < 8:
        data = data.ljust(8, b"\x00")

    out: Dict[str, object] = {"raw": data[:8].hex().upper()}

    if kind == "status":
        flags = data[7]
        out.update(
            heat_mos=1 if flags & 0x80 else 0,
            precharge_mos=1 if flags & 0x40 else 0,
            discharge_mos=1 if flags & 0x20 else 0,
            charge_mos=1 if flags & 0x10 else 0,
            parallel_finished=1 if flags & 0x01 else 0,
            status_flags=flags,
        )

    elif kind == "telemetry":
        voltage = u16le(data, 0) / 10.0
        current = s16le(data, 2) / 10.0
        out.update(
            voltage=voltage,
            current=current,
            power=voltage * current,
            soc=u16le(data, 4) / 10.0,
            soh=u16le(data, 6) / 10.0,
        )

    elif kind == "cell_extrema":
        vmax = u16le(data, 0) / 1000.0
        vmin = u16le(data, 2) / 1000.0
        out.update(
            max_cell_voltage=vmax,
            min_cell_voltage=vmin,
            cell_delta=vmax - vmin,
            max_cell_temperature=s16le(data, 4) / 10.0,
            min_cell_temperature=s16le(data, 6) / 10.0,
        )

    elif kind == "limits":
        out.update(
            mos_temperature=s16le(data, 0) / 10.0,
            aux_temperature=s16le(data, 2) / 10.0,
            charge_current_limit=float(u16le(data, 4)),
            discharge_current_limit=float(u16le(data, 6)),
        )

    elif kind == "state":
        mode = data[0]
        fault = data[1]
        out.update(
            work_mode=mode,
            work_mode_text={0: "idle", 1: "charging", 2: "discharging"}.get(mode, "unknown"),
            fault_level=fault,
            fault_level_text={0: "no fault", 1: "minor fault", 2: "serious fault"}.get(fault, "unknown"),
            cycles=u16le(data, 2),
            balance_bitmap=u16le(data, 4),
            state_reserved=u16le(data, 6),
        )

    elif kind == "identity":
        out.update(
            firmware_marker=hex_marker(data[0:2]),
            hardware_marker=hex_marker(data[2:4]),
            revision_text=ascii_field(data[4:8]),
        )

    elif kind == "energy":
        out.update(
            charged_energy=u32le(data, 0) / 1000.0,
            discharged_energy=u32le(data, 4) / 1000.0,
        )

    elif kind == "serial_a":
        out["serial_a"] = ascii_field(data[0:8])

    elif kind == "serial_b":
        out["serial_b"] = ascii_field(data[0:8])

    elif kind == "fault_history_a":
        out.update(
            charge_over_voltage_count=u16le(data, 0),
            discharge_under_voltage_count=u16le(data, 2),
            short_circuit_count=u16le(data, 4),
            mos_over_temperature_count=u16le(data, 6),
        )

    elif kind == "fault_history_b":
        out.update(
            charge_over_current_count=u16le(data, 0),
            discharge_over_current_count=u16le(data, 2),
            charge_over_temperature_count=u16le(data, 4),
            discharge_over_temperature_count=u16le(data, 6),
        )

    return out


def decode_system_frame(can_id: int, data: bytes) -> Dict[str, object]:
    if len(data) < 8:
        data = data.ljust(8, b"\x00")
    out: Dict[str, object] = {"raw": data[:8].hex().upper()}

    if can_id == 0x351:
        out.update(
            max_charge_voltage=u16le(data, 0) / 10.0,
            max_charge_current=u16le(data, 2) / 10.0,
            max_discharge_current=u16le(data, 4) / 10.0,
            battery_low_voltage=u16le(data, 6) / 10.0,
        )
    elif can_id == 0x355:
        out.update(soc=float(u16le(data, 0)), soh=float(u16le(data, 2)))
    elif can_id == 0x356:
        voltage = u16le(data, 0) / 100.0
        current = s16le(data, 2) / 10.0
        out.update(
            voltage=voltage,
            current=current,
            power=voltage * current,
            temperature=s16le(data, 4) / 10.0,
        )
    elif can_id == 0x359:
        out["alarm_bytes"] = data[:8].hex().upper()
    elif can_id == 0x35C:
        flags = data[0]
        out.update(
            charging_allowed=1 if flags & 0x80 else 0,
            discharging_allowed=1 if flags & 0x40 else 0,
            force_charge_1=1 if flags & 0x20 else 0,
            force_charge_2=1 if flags & 0x10 else 0,
            full_charge_request=1 if flags & 0x08 else 0,
        )
    elif can_id == 0x35E:
        out.update(
            manufacturer_id=ascii_field(data[0:5]),
            cell_manufacturer_code=data[5],
            cell_manufacturer=CELL_MANUFACTURERS.get(data[5], "unknown"),
            capacity_ah=u16le(data, 6) / 10.0,
        )
    elif can_id == 0x361:
        vmax = u16le(data, 0) / 1000.0
        vmin = u16le(data, 2) / 1000.0
        out.update(
            max_cell_voltage=vmax,
            min_cell_voltage=vmin,
            cell_delta=vmax - vmin,
            max_cell_temperature=s16le(data, 4) / 10.0,
            min_cell_temperature=s16le(data, 6) / 10.0,
        )
    elif can_id == 0x363:
        out.update(
            software_word=hex_marker(data[0:2]),
            hardware_protocol_word=hex_marker(data[2:4]),
        )
    elif can_id == 0x364:
        out.update(
            modules_normal=data[0],
            modules_charge_disabled=data[1],
            modules_discharge_disabled=data[2],
            modules_communication_disconnected=data[3],
            modules_total=data[4],
        )
    elif can_id == 0x371:
        out.update(
            array_charge_current_limit=u16le(data, 0) / 10.0,
            array_discharge_current_limit=u16le(data, 2) / 10.0,
        )
    return out
