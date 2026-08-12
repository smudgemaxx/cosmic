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
import Quickshell.Services.Mpris



PanelWindow {
  id: root
  color: "#1e1e2e"
  property string fontName: "Caskaydia Cove Nerd Font"
  property int fontSize: 16
  property var workspaces: Hyprland.workspaces.values
  property var extraWorkspaces: workspaces.filter(w => w.id > 5).map(w => w.id)
  property var displayList: [1, 2, 3, 4, 5].concat(extraWorkspaces)

  anchors {
    top: true
    left: true
    right: true
  }
  implicitHeight: 35

  PopupWindow {
    id: popup
    anchor.window: root
    anchor.rect.x: parentWindow.width / 2 - width / 2
    anchor.rect.y: parentWindow.height
    width: 500
    height: 500
    visible: false
    grabFocus: true
      Rectangle {
        anchors.centerIn: parent
        width: 100
        height: 100
        Text {
          text: "Hello World"
          anchors.centerIn: parent
        }
      }
  }

  Row {

    id: leftRow
    anchors.left: parent.left
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 18

    Repeater {
      model: root.displayList

      Text {
        property var ws: root.workspaces.find(w => w.id === modelData)
        property bool wsExists: ws !== undefined
        property bool wsFocused: ws ? ws.focused : false
        property color activeColor: "#cdd6f4"

        text: wsFocused ? "󱓻" : modelData.toString()
        color: !wsExists ? Qt.darker(activeColor, 1.5) : activeColor
        font.family: root.fontName
        font.pixelSize: root.fontSize

        MouseArea {
          anchors.fill: parent
          onClicked: ws.activate()
        }
      }
    }
  }


  Text {
    id: clock
    anchors.centerIn: parent
    color: "#cdd6f4"
    font.family: root.fontName
    font.pixelSize: root.fontSize

    Process {
      id: clockProc
      running: true
      command: ["date", "+%A %I:%M %p"]
      stdout: StdioCollector {
        onStreamFinished: clock.text = this.text
      }
    }
    Timer {
      running: true
      interval: 5000
      repeat: true
      onTriggered: clockProc.running = true
    }

    MouseArea {
      anchors.fill: parent
      onClicked: popup.visible = true
    }
  }

  Row {

    layoutDirection: Qt.RightToLeft
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: 10
    spacing: 15

    Text {
      id: battery
      property var device: UPower.displayDevice
      property var chargingStatus: device.state
      property var percentage: Math.floor( device.percentage * 100 )
      property var iconNumber: percentage != 100 ? Math.floor( percentage/10 ) : 9
      property var chargingIcons: ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
      property var dischargingIcons: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
      text: chargingStatus == 1 ? `${chargingIcons[iconNumber]} ${percentage}%` : ( chargingStatus == 2 ? `${dischargingIcons[iconNumber]} ${percentage}%`  : ` ${percentage}%` )
      color: "#cdd6f4"
      font.family: root.fontName
      font.pixelSize: root.fontSize
    }

    Process {
      id: brightnessctl
      running: true
      command: [ "brightnessctl", "g" ]
      stdout: StdioCollector {
        onStreamFinished: brightnessText.brightness = Math.round( ( this.text / 96000 ) * 100 )
      }
    }


    Text {
      id: brightnessText
      color: "#cdd6f4"
      font.family: root.fontName
      font.pixelSize: root.fontSize
      property var brightness
      text: `󰃠  ${brightness}%`
      MouseArea {
        anchors.fill: parent
        onWheel: (wheel) => {
          if (wheel.angleDelta.y > 0) {
            Quickshell.execDetached(["brightnessctl", "set", "1%-"])
            brightnessctl.running = true
          } else if (wheel.angleDelta.y < 0) {
            Quickshell.execDetached(["brightnessctl", "set", "1%+"])
            brightnessctl.running = true
          }
        }
      }
    }

    Text {
      id: sound
      PwObjectTracker {
        objects: [ Pipewire.defaultAudioSink]
      }
      property var node: Pipewire.defaultAudioSink
      property bool ready: node ? node.ready: false
      property var volume: node ? node.audio.volume : false
      property var iconNumber:  Math.min(icons.length - 1, Math.floor((volume * 100) / 33))
      property var icons: ["", "", ""]

      color: "#cdd6f4"
      font.family: root.fontName
      font.pixelSize: root.fontSize
      
      text: Math.round(volume * 100) != 0 ? `${icons[iconNumber]}  ${Math.round(volume * 100)}%`: "  0"
      
      MouseArea {
        anchors.fill: parent
        onWheel: (wheel) => {
          if (wheel.angleDelta.y > 0) {
            sound.node.audio.volume = Math.max(0, Math.min(1, sound.node.audio.volume - 0.005))
          } else if (wheel.angleDelta.y < 0) {
            sound.node.audio.volume = Math.max(0, Math.min(1, sound.node.audio.volume + 0.005))
          }
        }
      }
    }

    Text {
      id: wifi
      color: "#cdd6f4"
      font.family: root.fontName
      font.pixelSize: root.fontSize
      property var wifiDevice: Networking.devices.values.find(d => d.type == 1)
      property var networks: wifiDevice ? wifiDevice.networks : false
      property var connectedNetwork: networks ? networks.values.find(n => n.connected === true): false
      property var name: connectedNetwork ? connectedNetwork.name : false
      property var icons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
      property var signalStrength: connectedNetwork ? connectedNetwork.signalStrength : false
      property var iconNumber:   Math.round( ( signalStrength * 100 ) / 20 )

      text: `${icons[ iconNumber ]}  ${name}` 

      MouseArea {
        anchors.fill: parent
        onClicked: {
          Quickshell.execDetached([ "alacritty", "-e", "nmtui"])
        }
      }
    }


    Text {
      id: bluetooth
      color: "#cdd6f4"
      font.family: root.fontName
      font.pixelSize: root.fontSize
      property var adapter: Bluetooth.defaultAdapter
      property var enabled: adapter ? adapter.enabled : false
      property var devices: adapter ? adapter.devices : false

      text: enabled ? "": "󰂲"

      MouseArea {
        anchors.fill: parent
        onClicked: {
          Quickshell.execDetached([ "alacritty", "-e", "bluetui"])

        }
      }
      
    }

    Row {
      id: trayGroup
      layoutDirection: Qt.RightToLeft
      spacing: 16
      anchors.verticalCenter: parent.verticalCenter

      property bool hovered: false
      property bool menuOpen: false
      property bool expanded: hovered || menuOpen

      HoverHandler {
        onHoveredChanged: trayGroup.hovered = hovered
      }

      Item {
        id: trayContentContainer
        height: 16
        width: trayGroup.expanded ? trayContent.implicitWidth : 0
        clip: true
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        anchors.verticalCenter: parent.verticalCenter

        Row {
          id: trayContent
          spacing: 16
          anchors.verticalCenter: parent.verticalCenter

          Repeater {
            id: systemTrayRepeater
            property var items: SystemTray.items
            model: items

            Image {
              id: systemTray
              source: modelData.icon
              width: 16
              height: 16
              anchors.verticalCenter: parent.verticalCenter

              QsMenuAnchor {
                id: menuAnchor
                anchor.item: systemTray
                menu: modelData.menu
                anchor.margins.top: root.implicitHeight
                onVisibleChanged: {
                  if ( visible  == true ) {
                    trayGroup.menuOpen = true
                  } else {
                    trayGroup.menuOpen = false
                  }
                }
              }
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  menuAnchor.open()
                }
                
              }
            }
          }
        }
      }

      Text {
        id: trayGroupIcon
        text: ""
        color: "#cdd6f4"
        font.family: root.fontName
        font.pixelSize: root.fontSize
      }
    }
  }
}



