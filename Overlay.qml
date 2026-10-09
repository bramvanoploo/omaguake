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

  // Shell IPC Target
  IpcHandler {
    target: "omaguake"
    function toggle(): void { root.toggle() }
    function show(): void { root.show() }
    function hide(): void { root.hide() }
    function open(): void { root.show() }
    function close(): void { root.hide() }
  }

  PanelWindow {
    id: panelWindow
    visible: root.slideProgress > 0.001 || root.opened
    anchors { top: true; left: true; right: true }
    color: "transparent"

    readonly property real screenW: screen ? screen.width : 1920
    readonly property real screenH: screen ? screen.height : 1080
    readonly property real panelH: Math.round(screenH * (config.heightPercent / 100.0))

    implicitHeight: panelH
    implicitWidth: screenW

    WlrLayershell.namespace: "omaguake"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Automatically hide on focus loss
    HyprlandFocusGrab {
      active: root.opened && root.slideProgress >= 0.95 && config.autoHideOnFocusLoss
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
      opacity: Math.max(0.1, root.slideProgress)

      // Main Background Card
      Rectangle {
        id: bgCard
        anchors.fill: parent
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: 1
        radius: Style.cornerRadius

        // Subtle gradient top bar shadow
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: 3
          color: Color.accent
          opacity: 0.8
        }
      }

      // Terminal Content Area
      Item {
        id: terminalArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: config.tabsPosition === "top" ? tabBar.bottom : parent.top
        anchors.bottom: config.tabsPosition === "bottom" ? tabBar.top : parent.bottom
        clip: true

        Repeater {
          model: root.tabs.length
          delegate: TerminalView {
            anchors.fill: parent
            visible: index === root.currentTabIndex
            activeTab: visible && root.opened
            tabId: String(root.tabs[index].id)
            bridgeScript: config.ptyBridgeScript
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
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: config.tabsPosition === "top" ? parent.top : undefined
        anchors.bottom: config.tabsPosition === "bottom" ? parent.bottom : undefined
        height: 38
        color: Qt.darker(Color.menu.background, 1.15)
        border.color: Color.menu.border
        border.width: 1

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
                width: tabLabel.implicitWidth + (closeBtn.visible ? 28 : 12) + 16
                height: 30
                radius: Style.cornerRadius > 0 ? 4 : 0
                color: isActive ? Color.menu.background : "transparent"
                border.color: isActive ? Color.accent : (tabHover.containsMouse ? Color.menu.border : "transparent")
                border.width: 1

                MouseArea {
                  id: tabHover
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: {
                    root.currentTabIndex = index
                  }
                }

                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: 8
                  spacing: 6

                  Text {
                    id: tabLabel
                    text: modelData.title
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: tabItem.isActive
                    color: tabItem.isActive ? Color.foreground : Color.muted
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  // Close button on tab
                  Rectangle {
                    id: closeBtn
                    visible: root.tabs.length > 1 && (tabItem.isActive || tabHover.containsMouse)
                    width: 16
                    height: 16
                    radius: 8
                    color: closeHover.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

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
        }

        // Pinned Controls on the Right: "+", External terminal, Settings, Minimize
        Row {
          id: rightPinnedControls
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6

          // Open in External Terminal button
          Button {
            text: "↗"
            tooltipText: "Open in standalone terminal (foot/xdg-terminal-exec)"
            fontSize: Style.font.caption
            onClicked: {
              Quickshell.execDetached(["omarchy-launch-terminal"])
            }
          }

          // Settings Button
          Button {
            text: "⚙"
            tooltipText: "Omaguake Settings"
            fontSize: Style.font.caption
            onClicked: root.openSettings()
          }

          // Slide Up / Minimize button
          Button {
            text: "▲"
            tooltipText: "Hide Omaguake (" + config.keybinding + ")"
            fontSize: Style.font.caption
            onClicked: root.hide()
          }

          // Pinned "+" button to open more tabs
          Rectangle {
            id: newTabBtn
            width: 30
            height: 30
            radius: Style.cornerRadius > 0 ? 4 : 0
            color: newTabHover.containsMouse ? Color.menu.selectedBackground : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
            border.color: Color.accent
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: "+"
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              color: Color.accent
            }

            MouseArea {
              id: newTabHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.createTab()
            }
          }
        }
      }
    }
  }

  function openSettings() {
    if (!settingsLoader.active) {
      settingsLoader.active = true
    } else if (settingsLoader.item) {
      settingsLoader.item.open = !settingsLoader.item.open
    }
  }

  // Settings Overlay Loader
  Loader {
    id: settingsLoader
    active: false
    source: Qt.resolvedUrl("SettingsOverlay.qml")
    onLoaded: {
      if (item) {
        item.bar = null
        item.anchorItem = container
        item.configManager = config
        item.open = true
      }
    }
  }
}
