import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "bramvanoploo.omaguake"

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace("file://", "").replace(/\/$/, "")

  ConfigManager {
    id: config
    pluginDir: root.pluginDir
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggleTerminal() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "bramvanoploo.omaguake"])
  }

  function toggleSettings() {
    if (!settingsLoader.active) {
      settingsLoader.active = true
    } else if (settingsLoader.item) {
      settingsLoader.item.open = !settingsLoader.item.open
    }
  }

  function injectSettings() {
    if (settingsLoader.item) {
      settingsLoader.item.bar = root.bar
      settingsLoader.item.anchorItem = button
      settingsLoader.item.configManager = config
      settingsLoader.item.open = true
    }
  }

  onBarChanged: if (settingsLoader.item) settingsLoader.item.bar = root.bar

  Loader {
    id: settingsLoader
    active: false
    source: Qt.resolvedUrl("SettingsOverlay.qml")
    onLoaded: root.injectSettings()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf120"
    slotSize: Style.bar.iconSlot
    tooltipText: "Omaguake Dropdown Terminal" + (config.keybinding ? " (" + config.keybinding + ")" : "") + "\nLeft-click: Toggle · Right-click: Settings"

    onPressed: function(btn) {
      if (btn === Qt.RightButton) {
        root.toggleSettings()
      } else if (btn === Qt.LeftButton) {
        root.toggleTerminal()
      }
    }
  }
}
