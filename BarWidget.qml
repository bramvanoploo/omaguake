import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "bramvanoploo.omaguake"

  readonly property string pluginDir: Qt.resolvedUrl(".").replace("file://", "").replace(/\/$/, "")

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
    if (settingsLoader.item) {
      settingsLoader.item.open = !settingsLoader.item.open
    }
  }

  Loader {
    id: settingsLoader
    active: true
    sourceComponent: Component {
      SettingsOverlay {
        bar: root.bar
        anchorItem: button
        configManager: config
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    fontFamily: Style.font.family
    horizontalMargin: 6
    tooltipText: "Omaguake Dropdown Terminal (" + config.keybinding + ")\nLeft-click: Toggle · Right-click: Settings"

    onPressed: function(btn) {
      if (btn === Qt.RightButton) {
        root.toggleSettings()
      } else if (btn === Qt.LeftButton) {
        root.toggleTerminal()
      }
    }
  }
}
