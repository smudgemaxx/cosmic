import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "./Singletons"

PanelWindow {

  id: root
  color: "transparent"
  property string fontName: "Caskaydia Cove Nerd Font"
  property int fontSize: 16

  property var screenWidth: 1920
  property var screenHeight: 1080

  implicitWidth: screenWidth
  implicitHeight: screenHeight / 1.5

  property var wallpaperDirectory: "/home/rs/.config/cosmic/walls/catppuccin"

  visible: LauncherState.open

  ListModel {
    id: nameModel
  }

  Process {
    id: lsProcess
    running: true
    property var output : ""
    property var files: []
    command: [ "ls" , wallpaperDirectory ]
    stdout: StdioCollector {
      onStreamFinished: {
        nameModel.clear()
        lsProcess.output = this.text
        lsProcess.files = lsProcess.output.split("\n").filter(f => f.trim() !== "" )

        for (let i = 0; i < lsProcess.files.length; i++) {
          nameModel.append({
            name: lsProcess.files[i],
            path: `${wallpaperDirectory}/${lsProcess.files[i]}`
          })
        }
      }
    }
  }

  RowLayout {
    id: rowLayout
    anchors.fill: parent


    ListView {
      id: wallListView

      cacheBuffer: 400
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
      orientation: ListView.Horizontal
      model: nameModel
      spacing: 20

      highlightRangeMode: ListView.StrictlyEnforceRange
      preferredHighlightBegin: width / 2 - 200
      preferredHighlightEnd: width / 2 + 200
      highlightMoveDuration: 250

      delegate: Rectangle {
        id: wallDelegate
        anchors.verticalCenter : parent.verticalCenter

        Behavior on width {
          NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
          }
        }
        Behavior on height {
          NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
          }
        }

        width: ListView.isCurrentItem ? 400: 300
        height: ListView.isCurrentItem ? root.implicitHeight : root.implicitHeight - 100
        color: "transparent"

        Image {
          anchors.fill: parent
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          source: model.path
          sourceSize.width: 400
          sourceSize.height: root.implicitHeight
          cache: true
        }

        MouseArea {
          anchors.fill: parent
          onClicked: {
            wallListView.currentIndex = index
            WallpaperState.current = model.path
          }        
        }
      }
    }
    }
}
