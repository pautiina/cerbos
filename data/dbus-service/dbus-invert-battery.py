#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

# Имя DBus сервиса Victron Energy Battery
BATTERY_SERVICE = "com.victronenergy.battery.socketcan_can0"


def invert_value(path):
    """Инвертирует значение по заданному пути DBus."""
    try:
        obj = bus.get_object(BATTERY_SERVICE, path)
        iface = dbus.Interface(obj, 'com.victronenergy.BusItem')
        value = iface.GetValue()
        iface.SetValue(-value)
        print(f"[OK] {path}: {value} -> {-value}")
    except Exception as e:
        print(f"[Ошибка] {path}: {e}")


def update_values():
    """Обновляет (инвертирует) значения для заданных путей."""
    invert_value("/Dc/0/Current")
    invert_value("/Dc/0/Power")
    return True  # Повторять таймер


# Настройка основного цикла DBus
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()

# Выполнять update_values каждую секунду
GLib.timeout_add_seconds(1, update_values)

print("DBus Inverter Service запущен…")
GLib.MainLoop().run()
