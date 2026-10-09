import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace("file://", "").replace(/\/$/, "")

  property bool opened: false
  property real slideProgress: 0.0

  ConfigManager {
    id: config
    pluginDir: root.pluginDir
  }

  // Tab management model: starts with 1 tab open
  property int currentTabIndex: 0
  property int nextTabId: 2
  property var tabs: [
    { id: 1, title: "1: Default Terminal", shellName: "bash" }
  ]

  property string terminalIcon: "\uf489"
  property string currentSchemeName: "Omaguake"

  FileView {
    id: currentSchemeFile
    path: root.pluginDir + "/current_scheme.txt"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var name = String(text() || "").trim()
      if (name.length > 0) {
        root.currentSchemeName = name
      }
    }
    onFileChanged: reload()
  }

  function open() { show() }
  function close() { hide() }
  function toggle() { opened ? hide() : show() }

  function show() {
    root.opened = true
    hideAnim.stop()
    showAnim.start()
  }

  function hide() {
    root.opened = false
    showAnim.stop()
    hideAnim.start()
  }

  function createTab() {
    var newId = nextTabId++
    var newTabs = tabs.slice()
    newTabs.push({
      id: newId,
      title: newId + ": Terminal",
      shellName: "bash"
    })
    tabs = newTabs
    currentTabIndex = tabs.length - 1
    Qt.callLater(function() {
      tabsFlick.contentX = Math.max(0, tabsRow.width - tabsFlick.width)
    })
  }

  function closeTab(index) {
    if (tabs.length <= 1) {
      // If closing the only tab, hide panel or reset
      root.hide()
      return
    }
    var newTabs = tabs.slice()
    newTabs.splice(index, 1)
    tabs = newTabs
    if (currentTabIndex >= tabs.length) {
      currentTabIndex = tabs.length - 1
    }
  }

  function updateTabTitle(index, newTitle) {
    if (index >= 0 && index < tabs.length) {
      var newTabs = tabs.slice()
      var shortTitle = newTitle
      if (shortTitle.indexOf(":") !== -1) {
        var parts = shortTitle.split(":")
        shortTitle = parts[parts.length - 1]
      }
      if (shortTitle.length > 25) shortTitle = shortTitle.substring(0, 22) + "…"
      newTabs[index] = {
        id: tabs[index].id,
        title: tabs[index].id + ": " + shortTitle,
        shellName: shortTitle
      }
      tabs = newTabs
    }
  }

  // Slide down / slide up animations
  NumberAnimation {
    id: showAnim
    target: root
    property: "slideProgress"
    to: 1.0
    duration: 250
    easing.type: Easing.OutCubic
  }

  NumberAnimation {
    id: hideAnim
    target: root
    property: "slideProgress"
    to: 0.0
    duration: 200
    easing.type: Easing.InCubic
  }

  // Hyprland Global Shortcuts
  GlobalShortcut {
    appid: "bramvanoploo.omaguake"
    name: "toggle"
    description: "Toggle Omaguake dropdown terminal"
    onPressed: root.toggle()
  }

  GlobalShortcut {
    appid: "bramvanoploo.omaguake"
    name: "show"
    description: "Show Omaguake dropdown terminal"
    onPressed: root.show()
  }

  GlobalShortcut {
    appid: "bramvanoploo.omaguake"
    name: "hide"
    description: "Hide Omaguake dropdown terminal"
    onPressed: root.hide()
  }

  // Shell IPC Targets
  IpcHandler {
    target: "omaguake"
    function toggle(): void { root.toggle() }
    function show(): void { root.show() }
    function hide(): void { root.hide() }
    function open(): void { root.show() }
    function close(): void { root.hide() }
    function newTab(): void { root.createTab() }
    function retheme(): void { root.reloadTheme() }
  }

  IpcHandler {
    target: "bramvanoploo.omaguake"
    function toggle(): void { root.toggle() }
    function show(): void { root.show() }
    function hide(): void { root.hide() }
    function open(): void { root.show() }
    function close(): void { root.hide() }
    function newTab(): void { root.createTab() }
    function retheme(): void { root.reloadTheme() }
  }

  Process {
    id: themeSyncProc
    command: [root.pluginDir + "/scripts/sync-theme.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim()
        if (name.length > 0) {
          root.currentSchemeName = name
        }
      }
    }
    onExited: function(exitCode, exitStatus) {
      root.notifyTabsRetheme()
    }
  }

  function reloadTheme() {
    if (!themeSyncProc.running) {
      themeSyncProc.command = [root.pluginDir + "/scripts/sync-theme.py"]
      themeSyncProc.running = true
    }
  }

  function notifyTabsRetheme() {
    if (terminalRepeater) {
      for (var i = 0; i < terminalRepeater.count; i++) {
        var item = terminalRepeater.itemAt(i)
        if (item && typeof item.reloadColorScheme === "function") {
          item.reloadColorScheme(root.currentSchemeName)
        }
      }
    }
  }

  onCurrentSchemeNameChanged: {
    root.notifyTabsRetheme()
  }

  Component.onCompleted: {
    root.reloadTheme()
  }

  Connections {
    target: Color
    function onBackgroundChanged() { root.reloadTheme() }
    function onForegroundChanged() { root.reloadTheme() }
  }

  Connections {
    target: config
    function onOverlayOpacityPercentChanged() {
      if (!themeSyncProc.running) {
        themeSyncProc.command = [
          root.pluginDir + "/scripts/sync-theme.py",
          "--opacity-percent",
          String(config.overlayOpacityPercent)
        ]
        themeSyncProc.running = true
      }
    }
  }

  property bool focusPrimed: false

  onOpenedChanged: {
    if (opened) {
      focusPrimed = false
      focusPrimeTimer.restart()
    } else {
      focusPrimeTimer.stop()
      focusPrimed = false
    }
  }

  Timer {
    id: focusPrimeTimer
    interval: 75
    repeat: false
    onTriggered: {
      if (root.opened) {
        root.focusPrimed = true
      }
    }
  }

  PanelWindow {
    id: panelWindow
    visible: root.slideProgress > 0.001 || root.opened
    anchors { top: true; left: true; right: true }
    margins {
      top: Style.bar.sizeHorizontal
    }
    color: "transparent"
    surfaceFormat.opaque: false

    readonly property real screenW: screen ? screen.width : 1920
    readonly property real screenH: screen ? screen.height : 1080
    readonly property real panelH: Math.round(screenH * (config.heightPercent / 100.0))

    implicitHeight: panelH
    implicitWidth: screenW

    mask: Region {
      x: 0
      y: 0
      width: panelWindow.width
      height: Math.max(0, Math.round(panelWindow.panelH * root.slideProgress))
    }

    WlrLayershell.namespace: "omaguake"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.opened
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Automatically hide on focus loss
    HyprlandFocusGrab {
      active: root.opened && root.focusPrimed && config.autoHideOnFocusLoss
      windows: [panelWindow]
      onCleared: {
        if (root.opened && config.autoHideOnFocusLoss) {
          root.hide()
        }
      }
    }

    // Sliding container item
    Item {
      id: container
      width: parent.width
      height: parent.height
      y: (root.slideProgress - 1.0) * parent.height
      opacity: Math.max(0.01, root.slideProgress) * container.cardOpacity

      readonly property real cardOpacity: {
        if (config && config.overlayOpacityPercent !== undefined) {
          return Math.max(0.20, Math.min(1.0, config.overlayOpacityPercent / 100.0))
        }
        var op = config ? config.systemActiveOpacity : 0.88
        if (op > 0 && op < 1.0) {
          return op >= 0.98 ? 0.90 : op
        }
        return 0.88
      }

      // Main Background Card
      Rectangle {
        id: bgCard
        anchors.fill: parent
        color: Color.background
        border.color: Color.muted
        border.width: 1
        radius: Style.cornerRadius
      }

      // Terminal Content Area
      Item {
        id: terminalArea
        width: parent.width
        y: config.tabsPosition === "top" ? tabBar.height : 0
        height: parent.height - tabBar.height
        clip: true

        Repeater {
          id: terminalRepeater
          model: root.tabs.length
          delegate: TerminalView {
            anchors.fill: parent
            visible: index === root.currentTabIndex
            activeTab: visible && root.opened
            tabId: String(root.tabs[index].id)
            schemeName: root.currentSchemeName
            onTitleUpdated: function(newTitle) {
              root.updateTabTitle(index, newTitle)
            }
            onProcessExited: function(code) {
              root.closeTab(index)
            }
          }
        }
      }

      // Tab Bar (Bottom by default, or Top when configured)
      Rectangle {
        id: tabBar
        width: parent.width
        height: 38
        y: config.tabsPosition === "top" ? 0 : parent.height - height
        color: Qt.rgba(Color.background.r * 0.75, Color.background.g * 0.75, Color.background.b * 0.75, Math.min(0.96, container.cardOpacity + 0.05))
        border.width: 0

        // Divider between tab bar and terminal
        Rectangle {
          width: parent.width
          height: 1
          y: config.tabsPosition === "top" ? parent.height - 1 : 0
          color: Color.muted
        }

        // Scrollable Tabs Area (Left-aligned)
        Flickable {
          id: tabsFlick
          anchors.left: parent.left
          anchors.right: rightPinnedControls.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.margins: 2
          clip: true
          contentWidth: tabsRow.width
          contentHeight: height
          flickableDirection: Flickable.HorizontalFlick
          boundsBehavior: Flickable.StopAtBounds

          MouseArea {
            anchors.fill: parent
            onWheel: function(wheel) {
              if (wheel.angleDelta.y !== 0) {
                tabsFlick.contentX = Math.max(0, Math.min(tabsRow.width - tabsFlick.width, tabsFlick.contentX - wheel.angleDelta.y))
              }
            }
          }

          Row {
            id: tabsRow
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 6

            Repeater {
              model: root.tabs
              delegate: Rectangle {
                id: tabItem
                readonly property bool isActive: index === root.currentTabIndex
                width: Math.max(Style.space(120), tabLabel.implicitWidth + (closeBtn.visible ? 28 : 12) + 20)
                height: 30
                radius: Style.cornerRadius > 0 ? 4 : 0
                color: isActive ? Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.85) : "transparent"
                border.color: isActive ? Color.accent : (tabHover.containsMouse ? Color.muted : "transparent")
                border.width: 1

                MouseArea {
                  id: tabHover
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: {
                    root.currentTabIndex = index
                  }
                }

                Text {
                  id: tabLabel
                  anchors.left: parent.left
                  anchors.leftMargin: 10
                  anchors.right: closeBtn.visible ? closeBtn.left : parent.right
                  anchors.rightMargin: 6
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.terminalIcon + " " + modelData.title
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: tabItem.isActive
                  color: tabItem.isActive ? Color.foreground : Color.muted
                  elide: Text.ElideRight
                }

                // Close button on tab
                Rectangle {
                  id: closeBtn
                  visible: root.tabs.length > 1 && (tabItem.isActive || tabHover.containsMouse)
                  anchors.right: parent.right
                  anchors.rightMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  width: 16
                  height: 16
                  radius: 8
                  color: closeHover.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "×"
                    font.pixelSize: 13
                    color: closeHover.containsMouse ? Color.urgent : Color.muted
                  }

                  MouseArea {
                    id: closeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.closeTab(index)
                  }
                }
              }
            }
          }
        }

        // Pinned Controls on the Right: "+", External terminal, Settings, Minimize
        Row {
          id: rightPinnedControls
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6

          // Slide Up / Minimize button
          Button {
            text: "▲"
            tooltipText: "Hide Omaguake (" + config.keybinding + ")"
            fontSize: Style.font.caption
            onClicked: root.hide()
          }

          // Pinned "+" button to open more tabs
          Button {
            id: newTabBtn
            text: "+"
            tooltipText: "Open new terminal tab"
            fontSize: Style.font.body
            onClicked: root.createTab()
          }
        }
      }
    }
  }
}
