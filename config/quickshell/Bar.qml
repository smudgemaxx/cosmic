//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import QtQuick
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.SystemTray
import "./Singletons"

// Flat top bar styled after waybar (33px, edge-to-edge).
//   left:   workspaces 1-5 (+ extras), fixed-width cells
//   center: clock
//   right:  tray · bluetooth · network · pulseaudio · backlight · battery
//           (battery sits at the screen edge)
PanelWindow {
  id: root
  color: Theme.base

  anchors {
    top: true
    left: true
    right: true
  }
  implicitHeight: 33

  // ============================================================ LEFT: workspaces
  Row {
    id: workspaceRow
    anchors {
      left: parent.left
      verticalCenter: parent.verticalCenter
      leftMargin: 10
    }
    spacing: 6

    property var workspaces: Hyprland.workspaces.values
    property var extraWorkspaces: workspaces.filter(w => w.id > 5).map(w => w.id)
    property var displayList: [1, 2, 3, 4, 5].concat(extraWorkspaces)

    Repeater {
      model: workspaceRow.displayList

      delegate: Item {
        id: wsCell
        required property int modelData
        width: 20
        height: root.implicitHeight

        property var ws: workspaceRow.workspaces.find(w => w.id === modelData)
        property bool wsFocused: ws ? ws.focused : false
        property bool wsOccupied: ws ? ws.toplevels.length > 0 : false

        Text {
          id: wsLabel
          anchors.centerIn: parent
          text: modelData.toString()
          color: wsFocused ? Theme.accent : Theme.text
          font.family: Theme.font
          font.pixelSize: 15
          font.weight: wsFocused ? Font.Bold : Font.Normal
          opacity: (!wsFocused && !wsOccupied) ? 0.5 : 1

          Behavior on color { ColorAnimation { duration: Theme.animFast } }
          Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }

        // active workspace indicator
        Rectangle {
          anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
          }
          width: 12
          height: 2
          radius: 1
          color: Theme.accent
          visible: wsFocused
        }

        MouseArea {
          anchors.fill: parent
          onClicked: if (wsCell.ws) wsCell.ws.activate()
        }
      }
    }
  }

  // ============================================================ CENTER: clock
  Text {
    id: clockText
    anchors.centerIn: parent
    color: Theme.text
    font.family: Theme.font
    font.pixelSize: 15

    MouseArea {
      anchors.fill: parent
      anchors.margins: -6
      onClicked: calendarPopup.visible = !calendarPopup.visible
    }
  }

  // ============================================================ RIGHT: modules
  // RTL row: first child is rightmost → battery is at the screen edge
  Row {
    id: rightRow
    layoutDirection: Qt.RightToLeft
    anchors {
      right: parent.right
      verticalCenter: parent.verticalCenter
      rightMargin: 14
    }
    spacing: 16

    // -------- battery (rightmost, at the edge) --------
    Text {
      id: batteryText
      anchors.verticalCenter: parent.verticalCenter
      text: batteryText.state == 1
        ? batteryText.chargingIcons[batteryText.iconNumber] + " " + batteryText.percentage + "%"
        : (batteryText.state == 2
          ? batteryText.dischargingIcons[batteryText.iconNumber] + " " + batteryText.percentage + "%"
          : " " + batteryText.percentage + "%")
      color: Theme.text
      font.family: Theme.font
      font.pixelSize: 15
      visible: batteryText.device !== null

      property var device: UPower.displayDevice
      property int state: device ? device.state : -1
      property int percentage: device ? Math.floor(device.percentage * 100) : 0
      property int iconNumber: percentage != 100 ? Math.floor(percentage / 10) : 9
      property var chargingIcons: ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
      property var dischargingIcons: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    }

    // -------- backlight --------
    Text {
      id: brightText
      anchors.verticalCenter: parent.verticalCenter
      text: "󰃠 " + brightText.percent + "%"
      color: Theme.text
      font.family: Theme.font
      font.pixelSize: 15

      property int percent: 0

      MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        onWheel: (wheel) => {
          if (wheel.angleDelta.y > 0) {
            Quickshell.execDetached(["brightnessctl", "set", "5%-"])
          } else if (wheel.angleDelta.y < 0) {
            Quickshell.execDetached(["brightnessctl", "set", "5%+"])
          }
          brightnessRefresh.running = true
        }
      }

      Process {
        id: brightnessRefresh
        running: true
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
          onStreamFinished: {
            const parts = this.text.trim().split(",")
            if (parts.length >= 4) {
              const pct = parseInt(parts[3])
              if (!isNaN(pct)) brightText.percent = pct
            }
          }
        }
      }

      Timer {
        running: true
        interval: 5000
        repeat: true
        onTriggered: brightnessRefresh.running = true
      }
    }

    // -------- pulseaudio --------
    Text {
      id: soundText
      anchors.verticalCenter: parent.verticalCenter
      text: soundText.muted ? "" : soundText.icon + " " + Math.round(soundText.volume * 100) + "%"
      color: Theme.text
      font.family: Theme.font
      font.pixelSize: 15

      PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
      }

      property var node: Pipewire.defaultAudioSink
      property bool muted: node ? node.audio.mute === true : false
      property real volume: node ? node.audio.volume : 0
      property int iconIndex: Math.min(2, Math.floor((volume * 100) / 34))
      property var icons: ["", "", ""]
      property string icon: icons[iconIndex]

      MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        onClicked: {
          if (soundText.node) soundText.node.audio.mute = !soundText.node.audio.mute
        }
        onWheel: (wheel) => {
          if (soundText.node) {
            const delta = wheel.angleDelta.y > 0 ? -0.02 : 0.02
            soundText.node.audio.volume = Math.max(0, Math.min(1, soundText.node.audio.volume + delta))
          }
        }
      }
    }

    // -------- network (wifi) --------
    Text {
      id: wifiText
      anchors.verticalCenter: parent.verticalCenter
      text: wifiText.connected ? wifiText.icon + " " + wifiText.name : "󰤮"
      color: Theme.text
      font.family: Theme.font
      font.pixelSize: 15
      visible: Networking.devices.values.find(d => d.type == 1) !== undefined

      property var wifiDevice: Networking.devices.values.find(d => d.type == 1)
      property var networks: wifiDevice ? wifiDevice.networks : false
      property var connectedNetwork: networks ? networks.values.find(n => n.connected === true) : false
      property bool connected: connectedNetwork !== undefined && connectedNetwork !== false
      property var name: connectedNetwork ? connectedNetwork.name : ""
      property int signalStrength: connectedNetwork ? Math.round(connectedNetwork.signalStrength * 100) : 0
      property string icon: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"][Math.min(4, Math.max(0, Math.floor(signalStrength / 20)))]

      MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        onClicked: Quickshell.execDetached(["alacritty", "-e", "nmtui"])
      }
    }

    // -------- bluetooth --------
    Text {
      id: btText
      anchors.verticalCenter: parent.verticalCenter
      text: btText.btActive ? "" : "󰂲"
      color: Theme.text
      font.family: Theme.font
      font.pixelSize: 15
      visible: Bluetooth.defaultAdapter !== null

      property bool btActive: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled === true : false

      MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        onClicked: Quickshell.execDetached(["alacritty", "-e", "bluetui"])
      }
    }

    // -------- tray (leftmost, expander icon with icons on hover) --------
    Item {
      id: trayGroup
      width: trayGroup.expanded ? trayContent.implicitWidth + 28 : 18
      height: 18
      property bool hovered: false
      property bool menuOpen: false
      property bool expanded: hovered || menuOpen

      Behavior on width { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

      HoverHandler {
        onHoveredChanged: trayGroup.hovered = hovered
      }

      Row {
        id: trayContent
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 16
        spacing: 17
        clip: true

        Repeater {
          id: systemTrayRepeater
          property var items: SystemTray.items
          model: items

          Image {
            id: trayIcon
            source: modelData.icon
            width: 12
            height: 12
            anchors.verticalCenter: parent.verticalCenter

            QsMenuAnchor {
              id: menuAnchor
              anchor.item: trayIcon
              menu: modelData.menu
              anchor.margins.top: root.implicitHeight
              onVisibleChanged: trayGroup.menuOpen = visible
            }

            MouseArea {
              anchors.fill: parent
              onClicked: menuAnchor.open()
            }
          }
        }
      }

      Text {
        id: trayCaret
        anchors {
          left: parent.left
          verticalCenter: parent.verticalCenter
        }
        text: ""
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 15
      }
    }
  }

  // ============================================================ calendar popup
  PopupWindow {
    id: calendarPopup
    visible: false
    grabFocus: true
    anchor.window: root
    anchor.rect.x: parentWindow.width / 2 - implicitWidth / 2
    anchor.rect.y: parentWindow.height + 8
    implicitWidth: 320
    implicitHeight: 440
    color: "transparent"

    function refresh() {
      popupDate = new Date()
      viewDate = new Date(popupDate.getFullYear(), popupDate.getMonth(), 1)
    }

    property date popupDate: new Date()
    property date viewDate: new Date()

    Rectangle {
      anchors.fill: parent
      radius: Theme.radius
      color: Theme.base
      border.color: Theme.surface1
      border.width: 1

      opacity: calendarPopup.visible ? 1 : 0
      scale: calendarPopup.visible ? 1 : 0.96

      Behavior on opacity { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

      // big time
      Text {
        id: popupTime
        anchors {
          top: parent.top
          horizontalCenter: parent.horizontalCenter
          topMargin: 18
        }
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 36
        font.weight: Font.Bold

        SystemClock {
          id: popupClock
          enabled: true
          precision: SystemClock.Seconds
          onDateChanged: popupTime.text = root.fmtTime(popupClock.date)
        }

        Component.onCompleted: text = root.fmtTime(new Date())
      }

      Text {
        id: popupDateText
        anchors {
          top: popupTime.bottom
          horizontalCenter: parent.horizontalCenter
          topMargin: 2
        }
        color: Theme.subtext1
        font.family: Theme.font
        font.pixelSize: 14
        text: {
          const days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
          const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
          return days[calendarPopup.popupDate.getDay()] + ", " + months[calendarPopup.popupDate.getMonth()] + " " + calendarPopup.popupDate.getDate()
        }
      }

      // month navigation
      Row {
        id: monthNav
        anchors {
          top: popupDateText.bottom
          left: parent.left
          right: parent.right
          topMargin: 14
          leftMargin: 18
          rightMargin: 18
        }

        Text {
          id: prevMonth
          text: ""
          color: Theme.subtext1
          font.family: Theme.font
          font.pixelSize: 13
          width: 26
          height: 26
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter

          MouseArea {
            anchors.fill: parent
            onClicked: {
              const d = calendarPopup.viewDate
              calendarPopup.viewDate = new Date(d.getFullYear(), d.getMonth() - 1, 1)
            }
          }
        }

        Text {
          id: monthLabel
          text: {
            const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
            return months[calendarPopup.viewDate.getMonth()] + " " + calendarPopup.viewDate.getFullYear()
          }
          color: Theme.text
          font.family: Theme.font
          font.pixelSize: 14
          font.weight: Font.DemiBold
          width: monthNav.width - prevMonth.width - nextMonth.width - 16
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          id: nextMonth
          text: ""
          color: Theme.subtext1
          font.family: Theme.font
          font.pixelSize: 13
          width: 26
          height: 26
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter

          MouseArea {
            anchors.fill: parent
            onClicked: {
              const d = calendarPopup.viewDate
              calendarPopup.viewDate = new Date(d.getFullYear(), d.getMonth() + 1, 1)
            }
          }
        }
      }

      // weekday header
      Row {
        id: weekdayRow
        anchors {
          top: monthNav.bottom
          left: parent.left
          right: parent.right
          topMargin: 8
          leftMargin: 18
          rightMargin: 18
        }
        spacing: 4

        Repeater {
          model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

          delegate: Text {
            required property string modelData
            text: modelData
            color: Theme.subtext0
            font.family: Theme.font
            font.pixelSize: 12
            width: 36
            height: 22
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }

      // calendar grid
      Grid {
        id: calGrid
        anchors {
          top: weekdayRow.bottom
          left: parent.left
          right: parent.right
          topMargin: 2
          leftMargin: 18
          rightMargin: 18
        }
        columns: 7
        rows: 6
        spacing: 4

        Repeater {
          model: 42

          delegate: Rectangle {
            id: cell
            required property int index
            width: 36
            height: 32
            radius: 8
            color: cell.cellToday ? Theme.accent : (cell.cellHovered ? Theme.surface1 : "transparent")

            property bool cellHovered: false
            property bool cellToday: {
              const vd = calendarPopup.viewDate
              const today = calendarPopup.popupDate
              return dayNum >= 1 && dayNum <= daysInMonth
                && dayNum === today.getDate()
                && vd.getMonth() === today.getMonth()
                && vd.getFullYear() === today.getFullYear()
            }
            property bool isDimmed: dayNum < 1 || dayNum > daysInMonth
            property int dayNum: index - firstOffset + 1
            property int firstOffset: (calendarPopup.viewDate.getDay() + 6) % 7
            property int daysInMonth: new Date(calendarPopup.viewDate.getFullYear(), calendarPopup.viewDate.getMonth() + 1, 0).getDate()
            property int prevDays: new Date(calendarPopup.viewDate.getFullYear(), calendarPopup.viewDate.getMonth(), 0).getDate()
            property string cellText: {
              if (dayNum < 1) return (prevDays + dayNum).toString()
              if (dayNum > daysInMonth) return (dayNum - daysInMonth).toString()
              return dayNum.toString()
            }

            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            Text {
              anchors.centerIn: parent
              text: cell.cellText
              color: cell.cellToday ? Theme.crust : (cell.isDimmed ? Theme.overlay0 : Theme.text)
              font.family: Theme.font
              font.pixelSize: 12
              font.weight: cell.cellToday ? Font.Bold : Font.Normal
            }

            HoverHandler {
              onHoveredChanged: cell.cellHovered = hovered
            }
          }
        }
      }

      Text {
        id: todayHint
        anchors {
          bottom: parent.bottom
          horizontalCenter: parent.horizontalCenter
          bottomMargin: 10
        }
        text: "today"
        color: Theme.subtext0
        font.family: Theme.font
        font.pixelSize: 11

        MouseArea {
          anchors.fill: parent
          onClicked: calendarPopup.refresh()
        }
      }
    }

    onVisibleChanged: {
      if (visible) refresh()
    }
  }

  // ============================================================ clock logic
  SystemClock {
    id: systemClock
    enabled: true
    precision: SystemClock.Minutes

    onDateChanged: clockText.text = fmtBarDate(systemClock.date)
  }

  // matches waybar's "{:L%A %I:%M %p}" → "FRIDAY 03:45 PM"
  function fmtBarDate(d) {
    const days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    return days[d.getDay()].toUpperCase() + " " + fmtTime(d)
  }

  function fmtTime(d) {
    let h = d.getHours()
    const ampm = h >= 12 ? "PM" : "AM"
    h = h % 12
    if (h === 0) h = 12
    const hh = String(h).padStart(2, "0")
    const m = String(d.getMinutes()).padStart(2, "0")
    return hh + ":" + m + " " + ampm
  }

  Component.onCompleted: clockText.text = fmtBarDate(new Date())
}