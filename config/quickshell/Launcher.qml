import Quickshell
import QtQuick

PanelWindow {

  id: root
  color: "#1e1e2e"
  property string fontName: "Caskaydia Cove Nerd Font"
  property int fontSize: 16

  property var screenWidth: 1920
  property var screenHeight: 1080

  implicitWidth: screenWidth / 2
  implicitHeight: screenHeight / 2

  visible: false

  Item {
    anchors.fill: parent
    Image {
      fillMode: Image.PreserveAspectFit
      source: "file:///home/rs/.config/cosmic/walls/catppuccin/max.png"
      width: root.implicitWidth
      height: root.implicitHeight
    }
  }

}
