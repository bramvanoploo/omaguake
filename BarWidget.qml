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

  property bool settingsOpen: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggleTerminal() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "bramvanoploo.omaguake"])
  }

  function toggleSettings() {
    settingsOpen = !settingsOpen
  }

  function close() {
    settingsOpen = false
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf489"
    slotSize: Style.bar.iconSlot
    tooltipText: "Omaguake Dropdown Terminal" + (config.keybinding ? " (" + config.keybinding + ")" : "") + "\nLeft-click: Toggle · Right-click: Settings"

    onPressed: function(button) {
      if (button === Qt.RightButton) {
        root.toggleSettings()
      } else if (button === Qt.LeftButton) {
        root.toggleTerminal()
      }
    }
  }

  SettingsOverlay {
    id: settingsPopup
    anchorItem: root
    bar: root.bar
    owner: root
    configManager: config
    open: root.settingsOpen
  }

  IpcHandler {
    target: "omaguake.bar"
    function toggleSettings(): void { root.toggleSettings() }
    function openSettings(): void { root.settingsOpen = true }
    function closeSettings(): void { root.settingsOpen = false }
  }
}
