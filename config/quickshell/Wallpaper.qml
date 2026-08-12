import QtQuick
import Quickshell
import Quickshell.Wayland
import "./Singletons"

PanelWindow {
  id: wallpaperWindow
  WlrLayershell.layer: WlrLayer.Background
  exclusionMode: ExclusionMode.Ignore
  anchors {
    top: true
    bottom: true
    right: true
    left: true 
  }

  Image {
    anchors.fill: parent
    cache: false
    source: WallpaperState.current
    fillMode: Image.PreserveAspectCrop

  }

}
