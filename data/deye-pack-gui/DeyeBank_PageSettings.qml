import QtQuick
import QtQuick.Layouts
import Victron.VenusOS

Page {
    id: root
    title: "Deye Battery Bank"

    readonly property string bankServiceUid:
        BackendConnection.serviceUidFromName("com.victronenergy.deyebank_can0", 0)

    property var packList: []

    function rebuildPackList() {
        var list = []

        if (batteriesItem.valid && batteriesItem.value) {
            var arr = batteriesItem.value

            for (var i = 0; i < arr.length; ++i) {
                var b = arr[i]

                if (b === undefined || b.id === undefined || b.instance === undefined)
                    continue

                if (String(b.id).indexOf("com.victronenergy.battery.deyepack_") !== 0)
                    continue

                list.push({
                    "id": String(b.id),
                    "instance": Number(b.instance),
                    "uid": BackendConnection.serviceUidFromName(String(b.id), Number(b.instance)),
                    "name": b.name ? String(b.name) : String(b.id),
                    "soc": b.soc,
                    "voltage": b.voltage,
                    "current": b.current,
                    "temperature": b.temperature
                })
            }
        }

        list.sort(function(a, b) { return a.instance - b.instance })
        root.packList = list
    }

    function fmt(v, digits, suffix) {
        if (v === undefined || v === null || isNaN(Number(v)))
            return "--"
        return Number(v).toFixed(digits) + (suffix || "")
    }

    VeQuickItem {
        id: batteriesItem
        uid: Global.system.serviceUid + "/Batteries"
        onValueChanged: root.rebuildPackList()
    }

    Component.onCompleted: root.rebuildPackList()

    // ---------------------------------------------------------------------
    // Bank detail pages
    // ---------------------------------------------------------------------

    Component {
        id: electricalPage

        Page {
            title: "Electrical & limits"

            GradientListView {
                model: VisibleItemModel {
                    ListText {
                        text: "SOC"
                        dataItem.uid: root.bankServiceUid + "/System/Soc"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " %" : "--"
                    }
                    ListText {
                        text: "SOH"
                        dataItem.uid: root.bankServiceUid + "/System/Soh"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " %" : "--"
                    }
                    ListText {
                        text: "Voltage"
                        dataItem.uid: root.bankServiceUid + "/System/Voltage"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(2) + " V" : "--"
                    }
                    ListText {
                        text: "System current"
                        dataItem.uid: root.bankServiceUid + "/System/Current"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " A" : "--"
                    }
                    ListText {
                        text: "Sum of pack currents"
                        dataItem.uid: root.bankServiceUid + "/PackCurrentSum"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " A" : "--"
                    }
                    ListText {
                        text: "Current mismatch"
                        dataItem.uid: root.bankServiceUid + "/CurrentMismatchAbs"
                        secondaryText: {
                            if (!dataItem.valid)
                                return "--"
                            var a = Number(dataItem.value)
                            return a.toFixed(1) + " A" + (a > 5 ? "  WARNING" : "")
                        }
                    }
                    ListText {
                        text: "Power"
                        dataItem.uid: root.bankServiceUid + "/System/Power"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(0) + " W" : "--"
                    }
                    ListText {
                        text: "Capacity"
                        dataItem.uid: root.bankServiceUid + "/System/CapacityAh"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " Ah" : "--"
                    }
                    ListText {
                        text: "Charge voltage limit"
                        dataItem.uid: root.bankServiceUid + "/System/MaxChargeVoltage"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " V" : "--"
                    }
                    ListText {
                        text: "Charge current limit"
                        dataItem.uid: root.bankServiceUid + "/System/MaxChargeCurrent"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " A" : "--"
                    }
                    ListText {
                        text: "Discharge current limit"
                        dataItem.uid: root.bankServiceUid + "/System/MaxDischargeCurrent"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " A" : "--"
                    }
                    ListText {
                        text: "Low voltage limit"
                        dataItem.uid: root.bankServiceUid + "/System/BatteryLowVoltage"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " V" : "--"
                    }
                }
            }
        }
    }

    Component {
        id: cellsPage

        Page {
            title: "Cells & temperatures"

            GradientListView {
                model: VisibleItemModel {
                    ListText {
                        text: "Maximum cell"
                        dataItem.uid: root.bankServiceUid + "/System/MaxCellVoltage"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(3) + " V" : "--"
                    }
                    ListText {
                        text: "Minimum cell"
                        dataItem.uid: root.bankServiceUid + "/System/MinCellVoltage"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(3) + " V" : "--"
                    }
                    ListText {
                        text: "Cell delta"
                        dataItem.uid: root.bankServiceUid + "/System/CellDelta"
                        secondaryText: {
                            if (!dataItem.valid)
                                return "--"
                            var mv = Number(dataItem.value) * 1000.0
                            return mv.toFixed(0) + " mV" + (mv > 100 ? "  WARNING" : "")
                        }
                    }
                    ListText {
                        text: "System temperature"
                        dataItem.uid: root.bankServiceUid + "/System/Temperature"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " °C" : "--"
                    }
                    ListText {
                        text: "Maximum cell temperature"
                        dataItem.uid: root.bankServiceUid + "/System/MaxCellTemperature"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " °C" : "--"
                    }
                    ListText {
                        text: "Minimum cell temperature"
                        dataItem.uid: root.bankServiceUid + "/System/MinCellTemperature"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " °C" : "--"
                    }
                    ListText {
                        text: "Cell manufacturer"
                        dataItem.uid: root.bankServiceUid + "/System/CellManufacturer"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                }
            }
        }
    }

    Component {
        id: systemPage

        Page {
            title: "System & firmware"

            GradientListView {
                model: VisibleItemModel {
                    ListText {
                        text: "Manufacturer ID"
                        dataItem.uid: root.bankServiceUid + "/System/ManufacturerId"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "System FW marker"
                        dataItem.uid: root.bankServiceUid + "/System/SoftwareWord"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "System HW / protocol"
                        dataItem.uid: root.bankServiceUid + "/System/HardwareProtocolWord"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Firmware mismatch"
                        dataItem.uid: root.bankServiceUid + "/FirmwareMismatch"
                        secondaryText: dataItem.valid
                            ? (Number(dataItem.value) === 0 ? "No" : "YES  WARNING")
                            : "--"
                    }
                    ListText {
                        text: "Hardware mismatch"
                        dataItem.uid: root.bankServiceUid + "/HardwareMismatch"
                        secondaryText: dataItem.valid
                            ? (Number(dataItem.value) === 0 ? "No" : "YES  WARNING")
                            : "--"
                    }
                    ListText {
                        text: "Modules normal"
                        dataItem.uid: root.bankServiceUid + "/System/ModulesNormal"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Modules total"
                        dataItem.uid: root.bankServiceUid + "/System/ModulesTotal"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Communication disconnected"
                        dataItem.uid: root.bankServiceUid + "/System/ModulesCommunicationDisconnected"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Charge disabled"
                        dataItem.uid: root.bankServiceUid + "/System/ModulesChargeDisabled"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Discharge disabled"
                        dataItem.uid: root.bankServiceUid + "/System/ModulesDischargeDisabled"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Charging allowed"
                        dataItem.uid: root.bankServiceUid + "/System/ChargingAllowed"
                        secondaryText: dataItem.valid
                            ? (Number(dataItem.value) === 1 ? "Yes" : "No")
                            : "--"
                    }
                    ListText {
                        text: "Discharging allowed"
                        dataItem.uid: root.bankServiceUid + "/System/DischargingAllowed"
                        secondaryText: dataItem.valid
                            ? (Number(dataItem.value) === 1 ? "Yes" : "No")
                            : "--"
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Dynamic pack pages
    // ---------------------------------------------------------------------

    Component {
        id: packListPage

        Page {
            id: packsPage
            title: "Deye Battery Packs"

            Flickable {
                anchors.fill: parent
                anchors.margins: 12
                clip: true
                contentWidth: width
                contentHeight: packColumn.height

                Column {
                    id: packColumn
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.packList

                        delegate: Rectangle {
                            id: packRow
                            width: packColumn.width
                            height: 78
                            radius: 8
                            color: rowMouse.pressed ? "#202024" : "#171719"
                            border.width: 1
                            border.color: "#2a2a2e"

                            property var pack: modelData

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 14

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Label {
                                        text: packRow.pack.name
                                        font.pixelSize: 17
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: "Instance " + packRow.pack.instance
                                        font.pixelSize: 11
                                        color: "#85858c"
                                        Layout.fillWidth: true
                                    }
                                }

                                Label {
                                    text: root.fmt(packRow.pack.soc, 0, " %")
                                    font.pixelSize: 17
                                    font.bold: true
                                }

                                Label {
                                    text: root.fmt(packRow.pack.voltage, 2, " V")
                                    font.pixelSize: 15
                                    color: "#b0b0b5"
                                }

                                Label {
                                    text: root.fmt(packRow.pack.current, 1, " A")
                                    font.pixelSize: 15
                                    color: "#b0b0b5"
                                }

                                Label {
                                    text: "›"
                                    font.pixelSize: 24
                                    color: "#77777d"
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                onClicked: Global.pageManager.pushPage(packSummaryPage, {
                                    "serviceUid": packRow.pack.uid,
                                    "batteryLabel": packRow.pack.name,
                                    "instance": packRow.pack.instance
                                })
                            }
                        }
                    }

                    Label {
                        width: packColumn.width
                        height: 60
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        visible: root.packList.length === 0
                        text: "No Deye physical packs detected"
                        color: "#85858c"
                        font.pixelSize: 16
                    }
                }
            }
        }
    }

    Component {
        id: packSummaryPage

        Page {
            id: ps
            property string serviceUid: ""
            property string batteryLabel: ""
            property int instance: -1

            title: batteryLabel.length > 0 ? batteryLabel : "Deye Pack"

            GradientListView {
                model: VisibleItemModel {
                    ListText {
                        text: "Connected"
                        dataItem.uid: ps.serviceUid + "/Connected"
                        secondaryText: dataItem.valid
                            ? (Number(dataItem.value) === 1 ? "Yes" : "No")
                            : "--"
                    }

                    ListText {
                        text: "Firmware version"
                        dataItem.uid: ps.serviceUid + "/Diagnostics/Deye/Revision"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }

                    ListText {
                        text: "FW marker"
                        dataItem.uid: ps.serviceUid + "/Diagnostics/Deye/FirmwareMarker"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }

                    ListText {
                        text: "HW marker"
                        dataItem.uid: ps.serviceUid + "/Diagnostics/Deye/HardwareMarker"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }

                    ListText {
                        text: "SOC"
                        dataItem.uid: ps.serviceUid + "/Soc"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " %" : "--"
                    }

                    ListText {
                        text: "Voltage"
                        dataItem.uid: ps.serviceUid + "/Dc/0/Voltage"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(2) + " V" : "--"
                    }

                    ListText {
                        text: "Current"
                        dataItem.uid: ps.serviceUid + "/Dc/0/Current"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(2) + " A" : "--"
                    }

                    ListText {
                        text: "Cell delta"
                        dataItem.uid: ps.serviceUid + "/Diagnostics/Deye/CellDelta"
                        secondaryText: {
                            if (!dataItem.valid)
                                return "--"
                            var mv = Number(dataItem.value) * 1000.0
                            return mv.toFixed(0) + " mV" + (mv > 100 ? "  WARNING" : "")
                        }
                    }

                    ListText {
                        text: "Fault"
                        dataItem.uid: ps.serviceUid + "/Diagnostics/Deye/FaultLevelText"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }

                    ListText {
                        text: "Identification"
                        secondaryText: "Serial / firmware / service  ›"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Global.pageManager.pushPage(packIdentificationPage, {
                                "serviceUid": ps.serviceUid,
                                "batteryLabel": ps.batteryLabel,
                                "instance": ps.instance
                            })
                        }
                    }

                    ListText {
                        text: "Electrical & cells"
                        secondaryText: "V / I / temperatures / limits  ›"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Global.pageManager.pushPage(packElectricalPage, {
                                "serviceUid": ps.serviceUid,
                                "batteryLabel": ps.batteryLabel
                            })
                        }
                    }

                    ListText {
                        text: "BMS status"
                        secondaryText: "MOS / parallel / mode  ›"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Global.pageManager.pushPage(packBmsPage, {
                                "serviceUid": ps.serviceUid,
                                "batteryLabel": ps.batteryLabel
                            })
                        }
                    }

                    ListText {
                        text: "History & faults"
                        secondaryText: "Cycles / energy / counters  ›"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Global.pageManager.pushPage(packHistoryPage, {
                                "serviceUid": ps.serviceUid,
                                "batteryLabel": ps.batteryLabel
                            })
                        }
                    }
                }
            }
        }
    }

    Component {
        id: packIdentificationPage
        Page {
            id: pi
            property string serviceUid: ""
            property string batteryLabel: ""
            property int instance: -1
            title: batteryLabel + " - Identification"

            GradientListView {
                model: VisibleItemModel {
                    ListText {
                        text: "Device instance"
                        secondaryText: String(pi.instance)
                    }
                    ListText {
                        text: "Serial"
                        dataItem.uid: pi.serviceUid + "/Serial"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Firmware version"
                        dataItem.uid: pi.serviceUid + "/Diagnostics/Deye/Revision"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "FW marker"
                        dataItem.uid: pi.serviceUid + "/Diagnostics/Deye/FirmwareMarker"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "HW marker"
                        dataItem.uid: pi.serviceUid + "/Diagnostics/Deye/HardwareMarker"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Product"
                        dataItem.uid: pi.serviceUid + "/ProductName"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Manufacturer"
                        dataItem.uid: pi.serviceUid + "/Manufacturer"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Service UID"
                        secondaryText: pi.serviceUid
                    }
                    ListText {
                        text: "Last CAN frame"
                        dataItem.uid: pi.serviceUid + "/Diagnostics/Deye/LastSeenSeconds"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " s ago" : "--"
                    }
                }
            }
        }
    }

    Component {
        id: packElectricalPage
        Page {
            id: pe
            property string serviceUid: ""
            property string batteryLabel: ""
            title: batteryLabel + " - Electrical"

            GradientListView {
                model: VisibleItemModel {
                    ListText {
                        text: "SOC"
                        dataItem.uid: pe.serviceUid + "/Soc"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " %" : "--"
                    }
                    ListText {
                        text: "SOH"
                        dataItem.uid: pe.serviceUid + "/Soh"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " %" : "--"
                    }
                    ListText {
                        text: "Voltage"
                        dataItem.uid: pe.serviceUid + "/Dc/0/Voltage"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(2) + " V" : "--"
                    }
                    ListText {
                        text: "Current"
                        dataItem.uid: pe.serviceUid + "/Dc/0/Current"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(2) + " A" : "--"
                    }
                    ListText {
                        text: "Power"
                        dataItem.uid: pe.serviceUid + "/Dc/0/Power"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(0) + " W" : "--"
                    }
                    ListText {
                        text: "Battery temperature"
                        dataItem.uid: pe.serviceUid + "/Dc/0/Temperature"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " °C" : "--"
                    }
                    ListText {
                        text: "MOS temperature"
                        dataItem.uid: pe.serviceUid + "/Diagnostics/Deye/MosTemperature"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " °C" : "--"
                    }
                    ListText {
                        text: "Aux / heater temperature"
                        dataItem.uid: pe.serviceUid + "/Diagnostics/Deye/AuxTemperature"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " °C" : "--"
                    }
                    ListText {
                        text: "Maximum cell"
                        dataItem.uid: pe.serviceUid + "/System/MaxCellVoltage"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(3) + " V" : "--"
                    }
                    ListText {
                        text: "Minimum cell"
                        dataItem.uid: pe.serviceUid + "/System/MinCellVoltage"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(3) + " V" : "--"
                    }
                    ListText {
                        text: "Cell delta"
                        dataItem.uid: pe.serviceUid + "/Diagnostics/Deye/CellDelta"
                        secondaryText: {
                            if (!dataItem.valid)
                                return "--"
                            var mv = Number(dataItem.value) * 1000.0
                            return mv.toFixed(0) + " mV" + (mv > 100 ? "  WARNING" : "")
                        }
                    }
                    ListText {
                        text: "Minimum cell temperature"
                        dataItem.uid: pe.serviceUid + "/System/MinCellTemperature"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " °C" : "--"
                    }
                    ListText {
                        text: "Maximum cell temperature"
                        dataItem.uid: pe.serviceUid + "/System/MaxCellTemperature"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " °C" : "--"
                    }
                    ListText {
                        text: "Charge current limit"
                        dataItem.uid: pe.serviceUid + "/Diagnostics/Deye/ChargeCurrentLimit"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " A" : "--"
                    }
                    ListText {
                        text: "Discharge current limit"
                        dataItem.uid: pe.serviceUid + "/Diagnostics/Deye/DischargeCurrentLimit"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " A" : "--"
                    }
                }
            }
        }
    }

    Component {
        id: packBmsPage
        Page {
            id: pb
            property string serviceUid: ""
            property string batteryLabel: ""
            title: batteryLabel + " - BMS status"

            GradientListView {
                model: VisibleItemModel {
                    ListText {
                        text: "Work mode"
                        dataItem.uid: pb.serviceUid + "/Diagnostics/Deye/WorkModeText"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Parallel negotiation"
                        dataItem.uid: pb.serviceUid + "/Diagnostics/Deye/ParallelFinished"
                        secondaryText: dataItem.valid
                            ? (Number(dataItem.value) === 1 ? "OK" : "Not finished")
                            : "--"
                    }
                    ListText {
                        text: "Charge MOS"
                        dataItem.uid: pb.serviceUid + "/Diagnostics/Deye/ChargeMos"
                        secondaryText: dataItem.valid
                            ? (Number(dataItem.value) === 1 ? "ON" : "OFF")
                            : "--"
                    }
                    ListText {
                        text: "Discharge MOS"
                        dataItem.uid: pb.serviceUid + "/Diagnostics/Deye/DischargeMos"
                        secondaryText: dataItem.valid
                            ? (Number(dataItem.value) === 1 ? "ON" : "OFF")
                            : "--"
                    }
                    ListText {
                        text: "Precharge MOS"
                        dataItem.uid: pb.serviceUid + "/Diagnostics/Deye/PrechargeMos"
                        secondaryText: dataItem.valid
                            ? (Number(dataItem.value) === 1 ? "ON" : "OFF")
                            : "--"
                    }
                    ListText {
                        text: "Heater MOS"
                        dataItem.uid: pb.serviceUid + "/Diagnostics/Deye/HeatMos"
                        secondaryText: dataItem.valid
                            ? (Number(dataItem.value) === 1 ? "ON" : "OFF")
                            : "--"
                    }
                    ListText {
                        text: "Balance bitmap"
                        dataItem.uid: pb.serviceUid + "/Diagnostics/Deye/BalanceBitmap"
                        secondaryText: dataItem.valid
                            ? "0x" + Number(dataItem.value).toString(16).toUpperCase()
                            : "--"
                    }
                    ListText {
                        text: "Fault level"
                        dataItem.uid: pb.serviceUid + "/Diagnostics/Deye/FaultLevel"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Fault"
                        dataItem.uid: pb.serviceUid + "/Diagnostics/Deye/FaultLevelText"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                }
            }
        }
    }

    Component {
        id: packHistoryPage
        Page {
            id: ph
            property string serviceUid: ""
            property string batteryLabel: ""
            title: batteryLabel + " - History & faults"

            GradientListView {
                model: VisibleItemModel {
                    ListText {
                        text: "Cycles"
                        dataItem.uid: ph.serviceUid + "/History/ChargeCycles"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Charged energy"
                        dataItem.uid: ph.serviceUid + "/History/ChargedEnergy"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(3) + " kWh" : "--"
                    }
                    ListText {
                        text: "Discharged energy"
                        dataItem.uid: ph.serviceUid + "/History/DischargedEnergy"
                        secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(3) + " kWh" : "--"
                    }
                    ListText {
                        text: "Charge overvoltage"
                        dataItem.uid: ph.serviceUid + "/Diagnostics/Deye/FaultCount/ChargeOverVoltage"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Charge overcurrent"
                        dataItem.uid: ph.serviceUid + "/Diagnostics/Deye/FaultCount/ChargeOverCurrent"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Charge overtemperature"
                        dataItem.uid: ph.serviceUid + "/Diagnostics/Deye/FaultCount/ChargeOverTemperature"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Discharge undervoltage"
                        dataItem.uid: ph.serviceUid + "/Diagnostics/Deye/FaultCount/DischargeUnderVoltage"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Discharge overcurrent"
                        dataItem.uid: ph.serviceUid + "/Diagnostics/Deye/FaultCount/DischargeOverCurrent"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Discharge overtemperature"
                        dataItem.uid: ph.serviceUid + "/Diagnostics/Deye/FaultCount/DischargeOverTemperature"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "MOS overtemperature"
                        dataItem.uid: ph.serviceUid + "/Diagnostics/Deye/FaultCount/MosOverTemperature"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                    ListText {
                        text: "Short circuit"
                        dataItem.uid: ph.serviceUid + "/Diagnostics/Deye/FaultCount/ShortCircuit"
                        secondaryText: dataItem.valid ? String(dataItem.value) : "--"
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Main bank overview
    // ---------------------------------------------------------------------

    GradientListView {
        model: VisibleItemModel {
            ListText {
                text: "Connected"
                dataItem.uid: root.bankServiceUid + "/Connected"
                secondaryText: dataItem.valid
                    ? (Number(dataItem.value) === 1 ? "Yes" : "No")
                    : "--"
            }

            ListText {
                text: "Pack count"
                dataItem.uid: root.bankServiceUid + "/PackCount"
                secondaryText: dataItem.valid ? String(dataItem.value) : "--"
            }

            ListText {
                text: "Online packs"
                dataItem.uid: root.bankServiceUid + "/OnlinePackCount"
                secondaryText: dataItem.valid ? String(dataItem.value) : "--"
            }

            ListText {
                text: "SOC"
                dataItem.uid: root.bankServiceUid + "/System/Soc"
                secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " %" : "--"
            }

            ListText {
                text: "Voltage"
                dataItem.uid: root.bankServiceUid + "/System/Voltage"
                secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(2) + " V" : "--"
            }

            ListText {
                text: "System current"
                dataItem.uid: root.bankServiceUid + "/System/Current"
                secondaryText: dataItem.valid ? Number(dataItem.value).toFixed(1) + " A" : "--"
            }

            ListText {
                text: "Current mismatch"
                dataItem.uid: root.bankServiceUid + "/CurrentMismatchAbs"
                secondaryText: {
                    if (!dataItem.valid)
                        return "--"
                    var a = Number(dataItem.value)
                    return a.toFixed(1) + " A" + (a > 5 ? "  WARNING" : "")
                }
            }

            ListText {
                text: "Cell delta"
                dataItem.uid: root.bankServiceUid + "/System/CellDelta"
                secondaryText: {
                    if (!dataItem.valid)
                        return "--"
                    var mv = Number(dataItem.value) * 1000.0
                    return mv.toFixed(0) + " mV" + (mv > 100 ? "  WARNING" : "")
                }
            }

            ListText {
                text: "Firmware mismatch"
                dataItem.uid: root.bankServiceUid + "/FirmwareMismatch"
                secondaryText: dataItem.valid
                    ? (Number(dataItem.value) === 0 ? "No" : "YES  WARNING")
                    : "--"
            }

            ListText {
                text: "Battery packs"
                secondaryText: root.packList.length > 0
                    ? String(root.packList.length) + " detected  ›"
                    : "None"

                MouseArea {
                    anchors.fill: parent
                    enabled: root.packList.length > 0
                    onClicked: Global.pageManager.pushPage(packListPage)
                }
            }

            ListText {
                text: "Electrical & limits"
                secondaryText: "Details  ›"
                MouseArea {
                    anchors.fill: parent
                    onClicked: Global.pageManager.pushPage(electricalPage)
                }
            }

            ListText {
                text: "Cells & temperatures"
                secondaryText: "Details  ›"
                MouseArea {
                    anchors.fill: parent
                    onClicked: Global.pageManager.pushPage(cellsPage)
                }
            }

            ListText {
                text: "System & firmware"
                secondaryText: "Details  ›"
                MouseArea {
                    anchors.fill: parent
                    onClicked: Global.pageManager.pushPage(systemPage)
                }
            }

            ListText {
                text: "GUI / backend"
                secondaryText: "v0.5.1 / monitor v0.1.2"
            }
        }
    }
}
