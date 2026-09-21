* Підключення Cerbo-S GX до АКБ Deye SE-G 5.1 Pro, яка безперебійно працює.

Перша складність полягає в підключенні до BMS. Налаштування VE.Can Port потрібно встановити на 500 кбіт/с, тоді Victron розпізнає BMS акумулятора.

Керування зарядом працює ідеально через BMS, але візуалізація в VRM не працює; заряджання та розряджання змінюються місцями на дисплеї. Але це мене насправді не турбує.

На початку була одна проблема: BMS або Multiplus періодично вимикали ESS без повідомлення про помилку з «незрозумілих» причин, і ми підключалися до мережі, незважаючи на те, що акумулятор заряджений.

Я вирішив цю проблему за допомогою модуля Node-Red, який автоматично вмикає ESS, коли він вимкнений.


mkdir -p /data/dbus-services
cd /data/dbus-services

запустити:
```dbus-spy```

```com.victronenergy.battery.socketcan_can0```


# Діагностика прямих даних Deye через CAN

Звичайна діагностика на 30 секунд:

```/data/deye_can_diag.sh can0 30 /tmp```

Для більш надійної вибірки краще використовувати хвилину:

```/data/deye_can_diag.sh can0 60 /tmp```

На виході отримуємо два файли приблизно такого виду:

```/tmp/deye-can-can0-20260921-xxxxxx.log```
```/tmp/deye-can-report-20260921-xxxxxx.txt```

Перший – повний сирий CAN, другий – вже розкодований звіт.

Якщо лог вже є, повторно нічого знімати не треба:

```/data/deye_can_diag.sh --file /tmp/deye-full.log /tmp```

Ключова частина звіту вийде приблизно такою:
```
Detected battery packs:        2

--- Battery #1 ---
Firmware marker:               200A
Hardware marker:               AA56
Version/text field:            7.06
Current:                       0.0 A
SOC:                           96.0 %
Cell delta:                    ~0.04 V
Pack charge current limit:     32 A
Pack discharge current limit:  100 A

--- Battery #2 ---
Firmware marker:               1602
Hardware marker:               AA56
Version/text field:            1.10
Current:                       0.0 A
SOC:                           99.0 %
Cell delta:                    0.140 V
Pack charge current limit:     10 A
Pack discharge current limit:  100 A

WARNING: firmware markers differ between battery packs.
OK: all observed battery hardware markers are identical (AA56).
WARNING: battery #2 has a large cell delta: 0.140 V

System current (0x356):        -2700.0 A
Sum of pack currents:          0.0 A
Difference:                    -2700.0 A

WARNING:
System current does not match sum of individual pack currents.
Possible causes:
  master/parallel aggregation problem
  incompatible battery firmware
  incompatible protocol revision
  ```
