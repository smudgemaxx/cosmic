import QtQuick
import Quickshell
import Quickshell.Wayland
import "./Singletons"

// Fullscreen background layer. Renders WallpaperState.current and crossfades
// smoothly whenever it changes (picker click, nextWallpaper, theme switch).
PanelWindow {
  id: wallpaperWindow
  WlrLayershell.layer: WlrLayer.Background
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  anchors {
    top: true
    bottom: true
    right: true
    left: true
  }

  property string current: WallpaperState.current

  // two stacked layers: one shows the incoming image while the other fades out
  Image {
    id: layerA
    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    cache: false
    asynchronous: true
    opacity: showLayerA ? 1 : 0

    Behavior on opacity {
      NumberAnimation {
        duration: Theme.animSlow
        easing.type: Easing.InOutCubic
      }
    }
  }

  Image {
    id: layerB
    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    cache: false
    asynchronous: true
    opacity: showLayerA ? 0 : 1

    Behavior on opacity {
      NumberAnimation {
        duration: Theme.animSlow
        easing.type: Easing.InOutCubic
      }
    }
  }

  property bool showLayerA: true

  function swap() {
    // the layer currently hidden gets the new source and fades in over the old one
    if (showLayerA) {
      layerB.source = wallpaperWindow.current
      layerB.opacity = 1
      layerA.opacity = 0
    } else {
      layerA.source = wallpaperWindow.current
      layerA.opacity = 1
      layerB.opacity = 0
    }
    showLayerA = !showLayerA
  }

  onCurrentChanged: {
    // keep the old wallpaper visible while the list is being reloaded
    if (wallpaperWindow.current === "") return

    if (layerA.source === "" && layerB.source === "") {
      // first wallpaper: just show it, no fade
      layerA.source = wallpaperWindow.current
      layerA.opacity = 1
      showLayerA = true
    } else {
      swap()
    }
  }
}