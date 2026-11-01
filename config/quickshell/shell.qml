//@ pragma UseQApplication
import Quickshell
import QtQuick
import Quickshell.Io
import "./Singletons"

ShellRoot {
  Bar {}
  Launcher {}
  Wallpaper {}

  IpcHandler {
    id: launcherIpc
    target: "launcher"

    function toggle() {
      LauncherState.open = !LauncherState.open
    }

    function open() {
      LauncherState.open = true
    }

    function close() {
      LauncherState.open = false
    }
  }
}