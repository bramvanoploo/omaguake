import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "i18n.js" as I18n

BarWidget {
  id: root
  moduleName: "bramvanoploo.omaguake"

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace("file://", "").replace(/\/$/, "")

  ConfigManager {
    id: config
    pluginDir: root.pluginDir
  }

  Connections {
    target: config
    function onLanguageChanged() {
      I18n.setLanguageOverride(config.language)
    }
  }

  property bool settingsOpen: false
  property bool depDialogOpen: false
  property bool isInstalled: false
  property bool isInstalling: false
  property bool pendingOpen: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: checkInstalledProc
    command: ["pacman", "-Q", "qmltermwidget"]
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.isInstalled = true
        if (root.pendingOpen) {
          root.pendingOpen = false
          root.toggleTerminal()
        }
      } else {
        root.isInstalled = false
        if (root.pendingOpen) {
          root.pendingOpen = false
          root.depDialogOpen = true
        }
      }
    }
  }

  function checkAndOpen() {
    if (root.isInstalling) {
      return
    }
    if (root.isInstalled) {
      root.toggleTerminal()
      return
    }
    root.pendingOpen = true
    if (!checkInstalledProc.running) {
      checkInstalledProc.command = ["pacman", "-Q", "qmltermwidget"]
      checkInstalledProc.running = true
    }
  }

  function startInstallation() {
    root.depDialogOpen = false
    root.isInstalling = true
    Quickshell.execDetached([root.pluginDir + "/scripts/install-dependency.sh"])
  }

  function toggleTerminal() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "bramvanoploo.omaguake"])
  }

  function toggleSettings() {
    settingsOpen = !settingsOpen
  }

  function close() {
    settingsOpen = false
    depDialogOpen = false
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf489"
    slotSize: Style.bar.iconSlot
    tooltipText: {
      var _ = config.language
      return I18n.t("bar_tooltip", { chord: config.keybinding ? " (" + config.keybinding + ")" : "" })
    }

    onPressed: function(button) {
      if (button === Qt.RightButton) {
        root.toggleSettings()
      } else if (button === Qt.LeftButton) {
        root.checkAndOpen()
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

  DependencyDialog {
    id: dependencyDialog
    open: root.depDialogOpen
    language: config.language
    onCanceled: {
      root.depDialogOpen = false
    }
    onConfirmed: {
      root.startInstallation()
    }
  }

  IpcHandler {
    target: "omaguake.bar"
    function toggleSettings(): void { root.toggleSettings() }
    function openSettings(): void { root.settingsOpen = true }
    function closeSettings(): void { root.settingsOpen = false }
    function checkDependency(): void { checkInstalledProc.running = true }
    function checkAndOpen(): void { root.checkAndOpen() }
    function openDependencyDialog(): void { root.depDialogOpen = true }
    function closeDependencyDialog(): void { root.depDialogOpen = false }
    function resetInstallState(): void {
      root.isInstalling = false
      checkInstalledProc.running = true
    }
  }

  Component.onCompleted: {
    checkInstalledProc.running = true
  }
}
