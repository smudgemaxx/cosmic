pragma Singleton
import Quickshell
import Quickshell.Io
import QtQml

// Single source of truth for wallpapers.
//
// - Resolves the active theme from <cosmic>/current-theme (same file the
//   scripts use), so the picker, bar and wallpaper always agree.
// - Holds the wall list for the active theme. Listing is done by the
//   launcher (a window, where Process is allowed) via populateWalls().
// - Keeps <cosmic>/walls/indices/<theme> in sync: picking a wallpaper here
//   updates the index file, and external changes (nextWallpaper script) are
//   watched and picked up live.
Singleton {
  id: state

  function normalize(p) {
    const parts = p.split("/")
    const out = []
    for (const part of parts) {
      if (part === "..") out.pop()
      else if (part !== "" && part !== ".") out.push(part)
    }
    return "/" + out.join("/")
  }

  // the cosmic dotfiles live at ~/.config/cosmic; derive from $HOME so it
  // works no matter how quickshell is launched (default config path is a
  // symlink, so shellDir/../.. is unreliable)
  readonly property string home: (Quickshell.env("HOME") || "").toString()
  readonly property string cosmicRoot: home.length > 0
    ? home + "/.config/cosmic"
    : normalize(Quickshell.shellDir + "/../..")
  readonly property string wallsRoot: cosmicRoot + "/walls"

  // ----- theme -----
  property string theme: "catppuccin"

  FileView {
    id: themeReader
    path: state.cosmicRoot + "/current-theme"
    blockLoading: true
    watchChanges: true

    onFileChanged: state.readTheme()
  }

  function readTheme() {
    const t = themeReader.text().trim()
    if (t.length > 0) state.theme = t
  }

  // ----- wall list for the active theme -----
  readonly property string wallDir: wallsRoot + "/" + theme

  ListModel {
    id: wallModel
  }
  property var wallList: wallModel

  // feed raw `ls` output into the model (called by the launcher)
  function populateWalls(raw) {
    const names = raw.split("\n").map(s => s.trim()).filter(s => s.length > 0 && !s.startsWith("."))
    wallModel.clear()
    for (const name of names) {
      const dot = name.lastIndexOf(".")
      const base = dot > 0 ? name.slice(0, dot) : name
      wallModel.append({
        name: name,
        baseName: base,
        path: wallDir + "/" + name,
        thumbPath: wallDir + "/.thumbs/" + base + ".jpg"
      })
    }
  }

  // ----- index (the wallpaper the scripts would apply) -----
  readonly property string indexFile: wallsRoot + "/indices/" + theme

  property int index: 0

  FileView {
    id: indexReader
    path: state.indexFile
    blockLoading: true
    watchChanges: true

    onPathChanged: state.readIndex()
    onFileChanged: state.readIndex()
  }

  function readIndex() {
    const raw = indexReader.text().trim()
    const parsed = parseInt(raw)
    if (!isNaN(parsed)) state.index = parsed
  }

  // ----- current wallpaper path -----
  property string current: {
    if (wallModel.count === 0) return ""
    const i = Math.min(Math.max(state.index, 0), wallModel.count - 1)
    return wallModel.get(i).path
  }

  // ----- apply: updates state + index file so scripts stay in sync -----
  function setCurrent(path) {
    for (let i = 0; i < wallModel.count; i++) {
      if (wallModel.get(i).path === path) {
        state.index = i
        indexWriter.setText(String(i))
        return
      }
    }
  }

  FileView {
    id: indexWriter
    path: state.indexFile
    blockLoading: true
  }

  // bootstrap (Component.onCompleted is not available inside Singleton)
  QtObject {
    Component.onCompleted: {
      state.readTheme()
      state.readIndex()
    }
  }
}