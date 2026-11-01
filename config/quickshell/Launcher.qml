import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "./Singletons"

// Wallpaper picker. Opens via `qs ipc call launcher toggle`.
// - Lists the active theme's wallpapers (same ordering the scripts use).
// - Thumbnails from .thumbs with graceful fallback to the full image.
// - Keyboard: ←/→ browse · ↵ apply · esc close · wheel to scroll.
PanelWindow {
  id: root
  color: "transparent"
  visible: LauncherState.open
  focusable: true
  exclusionMode: ExclusionMode.Ignore

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // entrance / exit motion
  property real openProgress: 0

  NumberAnimation {
    id: openAnim
    target: root
    property: "openProgress"
    to: 1
    duration: Theme.animMed
    easing.type: Easing.OutCubic
  }

  // list the active theme's wallpapers (same ordering the scripts use)
  Process {
    id: lsProcess
    running: true
    command: ["ls", WallpaperState.wallDir]
    stdout: StdioCollector {
      onStreamFinished: WallpaperState.populateWalls(this.text)
    }
  }

  // re-list when the theme changes
  Connections {
    target: WallpaperState
    function onThemeChanged() {
      lsProcess.running = true
    }
  }

  // click anywhere outside the panel to close
  Rectangle {
    id: dimLayer
    anchors.fill: parent
    color: "#000000"
    opacity: openProgress * 0.5

    MouseArea {
      anchors.fill: parent
      onClicked: LauncherState.open = false
    }
  }

  // ----- the panel -----
  Rectangle {
    id: panel
    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
      leftMargin: 28
      rightMargin: 28
      bottomMargin: 28
    }
    height: Math.round(Screen.height * 0.56)
    radius: Theme.radius + 6
    color: Theme.base
    border.color: Theme.surface1
    border.width: 1
    clip: true

    opacity: openProgress
    y: (1 - openProgress) * 48
    scale: 0.985 + openProgress * 0.015

    // ----- header -----
    RowLayout {
      id: header
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
        topMargin: 20
        leftMargin: 28
        rightMargin: 28
      }
      spacing: 14

      Text {
        text: "Wallpapers"
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 22
        font.weight: Font.Bold
      }

      Rectangle {
        id: themePill
        Layout.alignment: Qt.AlignVCenter
        width: pillText.implicitWidth + 22
        height: 24
        radius: 12
        color: Theme.surface0

        Text {
          id: pillText
          anchors.centerIn: parent
          text: WallpaperState.theme.toUpperCase()
          color: Theme.accent
          font.family: Theme.font
          font.pixelSize: 12
          font.weight: Font.DemiBold
        }
      }

      Item { Layout.fillWidth: true }

      Text {
        text: "← →  browse    ↵  apply    esc  close"
        color: Theme.subtext0
        font.family: Theme.font
        font.pixelSize: 12
        Layout.alignment: Qt.AlignVCenter
      }
    }

    // ----- wallpaper carousel -----
    ListView {
      id: wallList
      anchors {
        top: header.bottom
        left: parent.left
        right: parent.right
        bottom: captionBar.top
        topMargin: 6
        leftMargin: 40
        rightMargin: 40
      }
      orientation: ListView.Horizontal
      model: WallpaperState.wallList
      spacing: 18
      clip: true
      cacheBuffer: 400

      highlightRangeMode: ListView.StrictlyEnforceRange
      preferredHighlightBegin: width / 2 - 170
      preferredHighlightEnd: width / 2 + 170
      highlightMoveDuration: Theme.animMed

      focus: LauncherState.open

      Keys.onLeftPressed: {
        if (currentIndex > 0) currentIndex--
        positionViewAtIndex(currentIndex, ListView.Center)
      }
      Keys.onRightPressed: {
        if (currentIndex < count - 1) currentIndex++
        positionViewAtIndex(currentIndex, ListView.Center)
      }
      Keys.onReturnPressed: applyCurrent()
      Keys.onEscapePressed: LauncherState.open = false

      WheelHandler {
        id: listWheel
        property real acc: 0
        onWheel: (event) => {
          acc += event.angleDelta.y / 120
          if (Math.abs(acc) >= 1) {
            const dir = acc > 0 ? -1 : 1
            const target = Math.min(Math.max(wallList.currentIndex + dir, 0), wallList.count - 1)
            wallList.currentIndex = target
            wallList.positionViewAtIndex(target, ListView.Center)
            acc = 0
          }
        }
      }

      delegate: Item {
        id: card
        required property int index
        required property string path
        required property string name
        required property string baseName
        required property string thumbPath

        property bool hovered: false

        width: ListView.isCurrentItem ? 340 : 250
        height: wallList.height

        Behavior on width {
          NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic }
        }

        opacity: (ListView.isCurrentItem || hovered) ? 1 : 0.72
        Behavior on opacity {
          NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
        }

        // card background
        Rectangle {
          id: cardBg
          anchors {
            fill: parent
            topMargin: 12
            bottomMargin: 12
          }
          radius: Theme.radius
          color: hovered ? Theme.surface1 : Theme.surface0
          border.width: ListView.isCurrentItem ? 2 : 1
          border.color: ListView.isCurrentItem ? Theme.accent : Theme.surface1

          Behavior on color {
            ColorAnimation { duration: Theme.animFast }
          }
          Behavior on border.color {
            ColorAnimation { duration: Theme.animFast }
          }

          Image {
            id: thumb
            anchors.fill: parent
            anchors.margins: 6
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            clip: true
            source: card.thumbPath
            sourceSize.width: 400
            sourceSize.height: 300

            onStatusChanged: {
              if (thumb.status === Image.Error && thumb.source !== card.path) {
                thumb.source = card.path
              }
            }
          }

          // current wallpaper badge
          Rectangle {
            anchors {
              top: parent.top
              right: parent.right
              topMargin: 14
              rightMargin: 14
            }
            width: 26
            height: 26
            radius: 13
            color: Theme.accent
            visible: ListView.isCurrentItem

            scale: visible ? 1 : 0
            Behavior on scale {
              NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack }
            }

            Text {
              anchors.centerIn: parent
              text: "\uF00C"
              color: Theme.crust
              font.family: Theme.font
              font.pixelSize: 13
              font.weight: Font.Bold
            }
          }
        }

        HoverHandler {
          onHoveredChanged: card.hovered = hovered
        }

        MouseArea {
          anchors.fill: parent
          onClicked: {
            wallList.currentIndex = card.index
            wallList.positionViewAtIndex(card.index, ListView.Center)
            applyCurrent()
          }
        }
      }
    }

    // ----- caption / feedback bar -----
    Rectangle {
      id: captionBar
      anchors {
        left: parent.left
        right: parent.right
        bottom: parent.bottom
      }
      height: 56
      color: "transparent"

      // separator above the caption
      Rectangle {
        anchors {
          top: parent.top
          left: parent.left
          right: parent.right
          leftMargin: 28
          rightMargin: 28
        }
        height: 1
        color: Theme.surface1
        opacity: 0.7
      }

      RowLayout {
        anchors {
          fill: parent
          leftMargin: 28
          rightMargin: 28
        }
        spacing: 10

        Text {
          id: currentName
          text: {
            const i = wallList.currentIndex
            return i >= 0 && i < wallList.count ? wallList.model.get(i).name : "—"
          }
          color: Theme.text
          font.family: Theme.font
          font.pixelSize: 15
          font.weight: Font.DemiBold
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        Text {
          id: appliedToast
          text: "✓ applied"
          color: Theme.green
          font.family: Theme.font
          font.pixelSize: 13
          font.weight: Font.DemiBold
          opacity: 0

          Behavior on opacity {
            NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic }
          }
        }
      }
    }

    // keep the applied toast visible for a moment
    Timer {
      id: toastTimer
      interval: 1600
      onTriggered: appliedToast.opacity = 0
    }

    function showToast() {
      appliedToast.opacity = 1
      toastTimer.restart()
    }
  }

  // ----- apply current wallpaper -----
  function applyCurrent() {
    const i = wallList.currentIndex
    if (i < 0 || i >= wallList.count) return
    const entry = wallList.model.get(i)
    WallpaperState.setCurrent(entry.path)
    panel.showToast()
  }

  onVisibleChanged: {
    if (visible) {
      lsProcess.running = true
      openProgress = 0
      openAnim.restart()
      wallList.currentIndex = Math.min(Math.max(WallpaperState.index, 0), wallList.count - 1)
      wallList.positionViewAtIndex(wallList.currentIndex, ListView.Center)
    } else {
      openProgress = 0
    }
  }
}