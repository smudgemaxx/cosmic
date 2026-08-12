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
    target: "launcher"
    function toggle(): void {
      LauncherState.open = !LauncherState.open
    }
  }
}
