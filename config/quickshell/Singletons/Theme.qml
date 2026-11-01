pragma Singleton
import Quickshell
import QtQuick

// Central palette + styling tokens.
// Catppuccin Mocha by default — swap the values here and every widget follows.
Singleton {
  readonly property string font: "Caskaydia Cove Nerd Font"
  readonly property int fontSize: 16

  // --- backgrounds ---
  readonly property color base: "#1e1e2e"
  readonly property color mantle: "#181825"
  readonly property color crust: "#11111b"
  readonly property color surface0: "#313244"
  readonly property color surface1: "#45475a"
  readonly property color surface2: "#585b70"

  // --- text ---
  readonly property color text: "#cdd6f4"
  readonly property color subtext1: "#bac2de"
  readonly property color subtext0: "#a6adc8"
  readonly property color overlay0: "#6c7086"

  // --- accents ---
  readonly property color accent: "#b4befe" // lavender
  readonly property color mauve: "#cba6f7"
  readonly property color blue: "#89b4fa"
  readonly property color green: "#a6e3a1"
  readonly property color yellow: "#f9e2af"
  readonly property color peach: "#fab387"
  readonly property color red: "#f38ba8"

  // --- motion ---
  readonly property int animFast: 120
  readonly property int animMed: 220
  readonly property int animSlow: 380
  readonly property int radius: 14
  readonly property int radiusSmall: 8
}