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
  property int overlayOpacityPercent: 90
  property string tabsPosition: "bottom"
  property string keybinding: ""
  property bool gesturesEnabled: false
  property int gestureFingers: 3
  property bool autoHideOnFocusLoss: true

  // System theme opacity tracking (from omasettings.json)
  property real systemActiveOpacity: 0.88

  function loadOmaSettings(raw) {
    if (!raw) return
    try {
      var d = JSON.parse(raw)
      if (d.hypr && d.hypr["active-opacity"] !== undefined) {
        var op = parseFloat(d.hypr["active-opacity"])
        if (op > 0 && op <= 1.0) {
          systemActiveOpacity = op
        }
      }
    } catch (e) {}
  }

  property var _omaSettingsFile: FileView {
    id: omaSettingsFile
    path: root.homeDir + "/.config/omarchy/omasettings.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadOmaSettings(text())
    onFileChanged: reload()
  }

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
      if (data.overlayOpacityPercent !== undefined) overlayOpacityPercent = parseInt(data.overlayOpacityPercent, 10) || 90
      if (data.tabsPosition !== undefined) tabsPosition = data.tabsPosition === "top" ? "top" : "bottom"
      if (data.keybinding !== undefined) keybinding = String(data.keybinding)
      if (data.gesturesEnabled !== undefined) gesturesEnabled = data.gesturesEnabled === true
      if (data.gestureFingers !== undefined) gestureFingers = parseInt(data.gestureFingers, 10) || 3
      if (data.autoHideOnFocusLoss !== undefined) autoHideOnFocusLoss = data.autoHideOnFocusLoss !== false
      settingsLoaded()
    } catch (e) {
      applyDefaults()
    }
  }

  function applyDefaults() {
    heightPercent = 50
    overlayOpacityPercent = 90
    tabsPosition = "bottom"
    keybinding = ""
    gesturesEnabled = false
    gestureFingers = 3
    autoHideOnFocusLoss = true
  }

  function saveSettings(obj) {
    if (obj.heightPercent !== undefined) heightPercent = obj.heightPercent
    if (obj.overlayOpacityPercent !== undefined) overlayOpacityPercent = obj.overlayOpacityPercent
    if (obj.tabsPosition !== undefined) tabsPosition = obj.tabsPosition
    if (obj.keybinding !== undefined) keybinding = obj.keybinding
    if (obj.gesturesEnabled !== undefined) gesturesEnabled = obj.gesturesEnabled
    if (obj.gestureFingers !== undefined) gestureFingers = obj.gestureFingers
    if (obj.autoHideOnFocusLoss !== undefined) autoHideOnFocusLoss = obj.autoHideOnFocusLoss

    var payload = {
      heightPercent: heightPercent,
      overlayOpacityPercent: overlayOpacityPercent,
      tabsPosition: tabsPosition,
      keybinding: keybinding,
      gesturesEnabled: gesturesEnabled,
      gestureFingers: gestureFingers,
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
