import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

QtObject {
  id: root

  property string pluginDir: ""
  readonly property string homeDir: Quickshell.env("HOME") || "/home/bram"
  readonly property string configPath: homeDir + "/.config/omarchy/plugins/bramvanoploo.omaguake/settings.json"
  readonly property string conflictCheckerScript: pluginDir + "/scripts/conflict-checker.py"
  readonly property string ptyBridgeScript: pluginDir + "/scripts/pty-bridge.py"

  property int heightPercent: 50
  property string tabsPosition: "bottom"
  property string keybinding: "CTRL + SPACE"
  property bool gesturesEnabled: true
  property bool autoHideOnFocusLoss: true

  signal settingsLoaded()
  signal settingsChanged()

  function loadSettings(raw) {
    if (!raw || !raw.trim()) {
      applyDefaults()
      return
    }
    try {
      var data = JSON.parse(raw)
      if (data.heightPercent !== undefined) heightPercent = parseInt(data.heightPercent, 10) || 50
      if (data.tabsPosition !== undefined) tabsPosition = data.tabsPosition === "top" ? "top" : "bottom"
      if (data.keybinding !== undefined) keybinding = String(data.keybinding)
      if (data.gesturesEnabled !== undefined) gesturesEnabled = data.gesturesEnabled === true
      if (data.autoHideOnFocusLoss !== undefined) autoHideOnFocusLoss = data.autoHideOnFocusLoss !== false
      settingsLoaded()
    } catch (e) {
      applyDefaults()
    }
  }

  function applyDefaults() {
    heightPercent = 50
    tabsPosition = "bottom"
    keybinding = "CTRL + SPACE"
    gesturesEnabled = true
    autoHideOnFocusLoss = true
  }

  function saveSettings(obj) {
    if (obj.heightPercent !== undefined) heightPercent = obj.heightPercent
    if (obj.tabsPosition !== undefined) tabsPosition = obj.tabsPosition
    if (obj.keybinding !== undefined) keybinding = obj.keybinding
    if (obj.gesturesEnabled !== undefined) gesturesEnabled = obj.gesturesEnabled
    if (obj.autoHideOnFocusLoss !== undefined) autoHideOnFocusLoss = obj.autoHideOnFocusLoss

    var payload = {
      heightPercent: heightPercent,
      tabsPosition: tabsPosition,
      keybinding: keybinding,
      gesturesEnabled: gesturesEnabled,
      autoHideOnFocusLoss: autoHideOnFocusLoss
    }

    settingsFile.setText(JSON.stringify(payload, null, 2) + "\n")
    settingsChanged()
  }

  property var _settingsFile: FileView {
    id: settingsFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.applyDefaults()
    onFileChanged: reload()
  }
}
