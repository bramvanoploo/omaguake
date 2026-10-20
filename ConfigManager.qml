import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "i18n.js" as I18n

QtObject {
  id: root

  property string pluginDir: ""
  readonly property string homeDir: Quickshell.env("HOME") || ""
  property string version: "0.9.10"
  readonly property string configPath: (homeDir ? homeDir : "~") + "/.config/omarchy/plugins/bramvanoploo.omaguake/settings.json"
  readonly property string conflictCheckerScript: pluginDir + "/scripts/conflict-checker.py"

  property int heightPercent: 50
  property int widthPercent: 100
  property int overlayOpacityPercent: 90
  property string tabsPosition: "bottom"
  property string language: ""
  property string keybinding: ""
  property bool gesturesEnabled: false
  property int gestureFingers: 3
  property bool autoHideOnFocusLoss: true

  onLanguageChanged: {
    I18n.setLanguageOverride(language)
  }

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

  property var _manifestFile: FileView {
    id: manifestFile
    path: root.pluginDir + "/manifest.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        var m = JSON.parse(text())
        if (m && m.version) root.version = String(m.version)
      } catch (e) {}
    }
  }

  signal settingsLoaded()
  signal settingsChanged()

  // Clamp persisted numbers so a hand-edited/corrupt settings.json can never
  // produce a zero-size panel, invisible overlay, or invalid gesture config.
  function clampInt(val, lo, hi, fallback) {
    var n = parseInt(val, 10)
    if (isNaN(n)) n = fallback
    return Math.max(lo, Math.min(hi, Math.round(n / 5) * 5))
  }

  function loadSettings(raw) {
    if (!raw || !raw.trim()) {
      applyDefaults()
      return
    }
    try {
      var data = JSON.parse(raw)
      if (data.heightPercent !== undefined) heightPercent = clampInt(data.heightPercent, 20, 100, 50)
      if (data.widthPercent !== undefined) widthPercent = clampInt(data.widthPercent, 20, 100, 100)
      if (data.overlayOpacityPercent !== undefined) overlayOpacityPercent = clampInt(data.overlayOpacityPercent, 20, 100, 90)
      if (data.tabsPosition !== undefined) tabsPosition = data.tabsPosition === "top" ? "top" : "bottom"
      if (data.language !== undefined) {
        language = String(data.language)
        I18n.setLanguageOverride(language)
      }
      if (data.keybinding !== undefined) keybinding = String(data.keybinding)
      if (data.gesturesEnabled !== undefined) gesturesEnabled = data.gesturesEnabled === true
      if (data.gestureFingers !== undefined) {
        var gf = parseInt(data.gestureFingers, 10)
        gestureFingers = (gf === 4) ? 4 : 3
      }
      if (data.autoHideOnFocusLoss !== undefined) autoHideOnFocusLoss = data.autoHideOnFocusLoss !== false
      settingsLoaded()
    } catch (e) {
      applyDefaults()
    }
  }

  function applyDefaults() {
    heightPercent = 50
    widthPercent = 100
    overlayOpacityPercent = 90
    tabsPosition = "bottom"
    language = ""
    I18n.setLanguageOverride("")
    keybinding = ""
    gesturesEnabled = false
    gestureFingers = 3
    autoHideOnFocusLoss = true
  }

  function saveSettings(obj) {
    if (obj.heightPercent !== undefined) heightPercent = obj.heightPercent
    if (obj.widthPercent !== undefined) widthPercent = obj.widthPercent
    if (obj.overlayOpacityPercent !== undefined) overlayOpacityPercent = obj.overlayOpacityPercent
    if (obj.tabsPosition !== undefined) tabsPosition = obj.tabsPosition
    if (obj.language !== undefined) {
      language = obj.language
      I18n.setLanguageOverride(language)
    }
    if (obj.keybinding !== undefined) keybinding = obj.keybinding
    if (obj.gesturesEnabled !== undefined) gesturesEnabled = obj.gesturesEnabled
    if (obj.gestureFingers !== undefined) gestureFingers = obj.gestureFingers
    if (obj.autoHideOnFocusLoss !== undefined) autoHideOnFocusLoss = obj.autoHideOnFocusLoss

    var payload = {
      heightPercent: heightPercent,
      widthPercent: widthPercent,
      overlayOpacityPercent: overlayOpacityPercent,
      tabsPosition: tabsPosition,
      language: language,
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
