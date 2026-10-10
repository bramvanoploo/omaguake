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

  // Tab management model: starts empty, tab 1 is created on completed
  property int currentTabIndex: 0
  property int nextTabId: 1
  property var tabs: []

  property string terminalIcon: "\uf489"
  property string currentSchemeName: "Omaguake"
  property var currentClipboardBinds: ({
    copy: [{ modmask: 64, key: "C" }],
    paste: [{ modmask: 64, key: "V" }]
  })

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

  // Watch Omarchy theme state files directly
  FileView {
    id: omarchyThemeNameFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: root.reloadTheme()
    onFileChanged: {
      reload()
      root.reloadTheme()
    }
  }

  FileView {
    id: omarchyColorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.reloadTheme()
    onFileChanged: {
      reload()
      root.reloadTheme()
    }
  }

  // Active inotifywait process monitoring Omarchy current directory across directory swaps
  Process {
    id: omarchyThemeWatcher
    command: [
      "inotifywait",
      "-m",
      "-q",
      "-e", "close_write,moved_to",
      "--format", "%f",
      Quickshell.env("HOME") + "/.local/state/omarchy/current"
    ]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var f = String(line || "").trim()
        if (f === "theme.name" || f === "theme" || f === "background" || f.indexOf("colors") !== -1) {
          root.reloadTheme()
        }
      }
    }
    onExited: function(exitCode, exitStatus) {
      Qt.callLater(function() {
        if (!omarchyThemeWatcher.running) {
          omarchyThemeWatcher.running = true
        }
      })
    }
  }

  FileView {
    id: clipboardBindsFile
    path: root.pluginDir + "/clipboard_binds.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var raw = String(text() || "").trim()
      if (raw.length > 0) {
        try {
          var parsed = JSON.parse(raw)
          if (parsed && (parsed.copy || parsed.paste)) {
            root.currentClipboardBinds = parsed
            root.notifyTabsClipboardBinds()
          }
        } catch(e) {}
      }
    }
    onFileChanged: reload()
  }

  function open() { show() }
  function close() { hide() }
  function toggle() { opened ? hide() : show() }

  function updateTerminalVisibility() {
    for (var i = 0; i < root.tabs.length; i++) {
      var item = root.tabs[i].termItem
      if (item) {
        var isCurrent = (i === root.currentTabIndex)
        item.visible = isCurrent
        item.activeTab = (isCurrent && root.opened)
      }
    }
  }

  function refreshActiveTerminal() {
    if (root.tabs.length > 0 && root.currentTabIndex >= 0 && root.currentTabIndex < root.tabs.length) {
      var item = root.tabs[root.currentTabIndex].termItem
      if (item && typeof item.refreshTerminal === "function") {
        item.refreshTerminal()
      }
    }
  }

  onCurrentTabIndexChanged: {
    root.updateTerminalVisibility()
    Qt.callLater(function() { root.refreshActiveTerminal() })
  }

  function show() {
    root.opened = true
    hideAnim.stop()
    showAnim.start()
    root.updateTerminalVisibility()
    Qt.callLater(function() { root.refreshActiveTerminal() })
  }

  function hide() {
    root.opened = false
    showAnim.stop()
    hideAnim.start()
    root.updateTerminalVisibility()
  }

  function createTab() {
    var newId = nextTabId++
    var term = terminalComponent.createObject(terminalArea, {
      tabId: String(newId),
      schemeName: root.currentSchemeName,
      clipboardBinds: root.currentClipboardBinds,
      visible: false,
      activeTab: false
    })

    if (!term) {
      console.warn("Failed to create TerminalView object for tab " + newId)
      return
    }

    term.titleUpdated.connect(function(newTitle) {
      root.updateTabTitleById(newId, newTitle)
    })
    term.commandUpdated.connect(function(cmdText) {
      root.updateLastCommandById(newId, cmdText)
    })
    term.processExited.connect(function(code) {
      root.closeTabById(newId)
    })
    term.newTabRequested.connect(function() {
      root.createTab()
    })
    term.closeTabRequested.connect(function() {
      root.closeTabById(newId)
    })
    term.nextTabRequested.connect(function() {
      root.nextTab()
    })
    term.previousTabRequested.connect(function() {
      root.previousTab()
    })
    term.switchTabNumberRequested.connect(function(tabNum) {
      root.selectTabByNumber(tabNum)
    })

    var newTabs = tabs.slice()
    newTabs.push({
      id: newId,
      title: (tabs.length + 1) + ": ~",
      shellName: "bash",
      cwd: "~",
      lastCommand: "",
      termItem: term
    })
    tabs = newTabs
    currentTabIndex = tabs.length - 1
    root.refreshTabTitles()
    root.updateTerminalVisibility()
    Qt.callLater(function() {
      root.refreshActiveTerminal()
      tabsFlick.contentX = Math.max(0, tabsRow.width - tabsFlick.width)
    })
  }

  function refreshTabTitles() {
    var changed = false
    var updated = tabs.slice()
    for (var i = 0; i < updated.length; i++) {
      var tab = updated[i]
      var tabPos = i + 1
      var cwd = tab.cwd || "~"
      var lastCmd = tab.lastCommand || ""
      var displayTitle = tabPos + ": " + cwd + (lastCmd ? " " + lastCmd : "")
      if (tab.title !== displayTitle) {
        updated[i] = {
          id: tab.id,
          title: displayTitle,
          shellName: tab.shellName || cwd,
          cwd: cwd,
          lastCommand: lastCmd,
          termItem: tab.termItem
        }
        changed = true
      }
    }
    if (changed) {
      tabs = updated
    }
  }

  function closeTab(index) {
    if (index < 0 || index >= tabs.length) return
    var tabToClose = tabs[index]
    if (tabToClose && tabToClose.termItem) {
      try {
        tabToClose.termItem.visible = false
        tabToClose.termItem.activeTab = false
        tabToClose.termItem.destroy()
      } catch(e) {}
    }

    if (tabs.length <= 1) {
      tabs = []
      root.hide()
      root.createTab()
      return
    }

    var newTabs = tabs.slice()
    newTabs.splice(index, 1)
    tabs = newTabs
    if (currentTabIndex >= tabs.length) {
      currentTabIndex = tabs.length - 1
    }
    root.refreshTabTitles()
    root.updateTerminalVisibility()
    Qt.callLater(function() { root.refreshActiveTerminal() })
  }

  function closeTabById(targetId) {
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].id === targetId) {
        closeTab(i)
        return
      }
    }
  }

  function updateTabTitleById(targetId, newTitle) {
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].id === targetId) {
        var tab = tabs[i]
        var shortTitle = String(newTitle || "").trim()
        if (shortTitle.indexOf(":") !== -1) {
          var parts = shortTitle.split(":")
          shortTitle = parts[parts.length - 1].trim()
        }
        var home = Quickshell.env("HOME") || ""
        if (home && shortTitle.indexOf(home) === 0) {
          shortTitle = "~" + shortTitle.slice(home.length)
        }
        var cwd = shortTitle || "~"
        var lastCmd = tab.lastCommand || ""
        var tabPos = i + 1
        var displayTitle = tabPos + ": " + cwd + (lastCmd ? " " + lastCmd : "")
        if (tab.title === displayTitle && tab.cwd === cwd) {
          return
        }
        var newTabs = tabs.slice()
        newTabs[i] = {
          id: tab.id,
          title: displayTitle,
          shellName: cwd,
          cwd: cwd,
          lastCommand: lastCmd,
          termItem: tab.termItem
        }
        tabs = newTabs
        return
      }
    }
  }

  function updateLastCommandById(targetId, cmdText) {
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].id === targetId) {
        var tab = tabs[i]
        var cwd = tab.cwd || "~"
        var trimmed = String(cmdText || "").trim()
        if (trimmed.length > 0) {
          if (tab.lastCommand === trimmed) {
            return
          }
          var tabPos = i + 1
          var displayTitle = tabPos + ": " + cwd + " " + trimmed
          var newTabs = tabs.slice()
          newTabs[i] = {
            id: tab.id,
            title: displayTitle,
            shellName: tab.shellName || cwd,
            cwd: cwd,
            lastCommand: trimmed,
            termItem: tab.termItem
          }
          tabs = newTabs
        }
        return
      }
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
    onFinished: root.refreshActiveTerminal()
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

  function selectTab(index) {
    if (index >= 0 && index < root.tabs.length) {
      root.currentTabIndex = index
      tabsFlick.ensureTabVisible(index)
    }
  }

  function nextTab() {
    if (root.tabs.length > 1) {
      root.selectTab((root.currentTabIndex + 1) % root.tabs.length)
    }
  }

  function previousTab() {
    if (root.tabs.length > 1) {
      root.selectTab((root.currentTabIndex - 1 + root.tabs.length) % root.tabs.length)
    }
  }

  function selectTabByNumber(tabNumber) {
    var idx = tabNumber - 1
    if (idx >= 0 && idx < root.tabs.length) {
      root.selectTab(idx)
    }
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
    function closeTab(index: int): void { root.closeTab(index) }
    function selectTab(index: int): void { root.selectTab(index) }
    function retheme(): void { root.reloadTheme() }
    function syncBinds(): void { root.reloadClipboardBinds() }
  }

  IpcHandler {
    target: "bramvanoploo.omaguake"
    function toggle(): void { root.toggle() }
    function show(): void { root.show() }
    function hide(): void { root.hide() }
    function open(): void { root.show() }
    function close(): void { root.hide() }
    function newTab(): void { root.createTab() }
    function closeTab(index: int): void { root.closeTab(index) }
    function selectTab(index: int): void { root.selectTab(index) }
    function retheme(): void { root.reloadTheme() }
    function syncBinds(): void { root.reloadClipboardBinds() }
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
          root.notifyTabsRetheme()
        }
      }
    }
    onExited: function(exitCode, exitStatus) {
      currentSchemeFile.reload()
      root.notifyTabsRetheme()
      if (root.themeReloadQueued) {
        root.themeReloadQueued = false
        Qt.callLater(function() { root.reloadTheme() })
      }
    }
  }

  Process {
    id: clipboardSyncProc
    command: [root.pluginDir + "/scripts/sync-clipboard-binds.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw.length > 0) {
          try {
            var parsed = JSON.parse(raw)
            if (parsed && (parsed.copy || parsed.paste)) {
              root.currentClipboardBinds = parsed
              root.notifyTabsClipboardBinds()
            }
          } catch(e) {}
        }
      }
    }
  }

  function reloadClipboardBinds() {
    if (!clipboardSyncProc.running) {
      clipboardSyncProc.command = [root.pluginDir + "/scripts/sync-clipboard-binds.py"]
      clipboardSyncProc.running = true
    }
  }

  function notifyTabsClipboardBinds() {
    for (var i = 0; i < root.tabs.length; i++) {
      var item = root.tabs[i].termItem
      if (item) {
        item.clipboardBinds = root.currentClipboardBinds
      }
    }
  }

  property bool themeReloadQueued: false

  Timer {
    id: themeDebounceTimer
    interval: 80
    repeat: false
    onTriggered: {
      if (themeSyncProc.running) {
        root.themeReloadQueued = true
        return
      }
      root.themeReloadQueued = false
      var cmd = [root.pluginDir + "/scripts/sync-theme.py"]
      if (config && config.overlayOpacityPercent !== undefined) {
        cmd.push("--opacity-percent", String(config.overlayOpacityPercent))
      }
      themeSyncProc.command = cmd
      themeSyncProc.running = true
    }
  }

  function reloadTheme() {
    themeDebounceTimer.restart()
  }

  function notifyTabsRetheme() {
    for (var i = 0; i < root.tabs.length; i++) {
      var item = root.tabs[i].termItem
      if (item && typeof item.reloadColorScheme === "function") {
        item.reloadColorScheme(root.currentSchemeName)
      }
    }
  }

  onCurrentSchemeNameChanged: {
    root.notifyTabsRetheme()
  }

  Component.onCompleted: {
    root.createTab()
    root.reloadTheme()
    root.reloadClipboardBinds()
  }

  Component.onDestruction: {
    if (omarchyThemeWatcher.running) {
      omarchyThemeWatcher.running = false
    }
    if (themeSyncProc.running) {
      themeSyncProc.running = false
    }
    if (clipboardSyncProc.running) {
      clipboardSyncProc.running = false
    }
  }

  Connections {
    target: Color
    function onBackgroundChanged() { root.reloadTheme() }
    function onForegroundChanged() { root.reloadTheme() }
  }

  Connections {
    target: config
    function onOverlayOpacityPercentChanged() {
      root.reloadTheme()
    }
  }

  property bool focusPrimed: false

  onOpenedChanged: {
    if (opened) {
      root.reloadTheme()
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
        root.refreshActiveTerminal()
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

    ShortcutInhibitor {
      id: shortcutInhibitor
      window: panelWindow
      enabled: root.opened
    }

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
      opacity: Math.max(0.01, root.slideProgress)

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

      // Terminal Content Area (Opacity setting applied specifically to terminal)
      Item {
        id: terminalArea
        width: parent.width
        y: config.tabsPosition === "top" ? tabBar.height : 0
        height: parent.height - tabBar.height
        clip: true
        opacity: container.cardOpacity

        // Terminal Background Card
        Rectangle {
          id: terminalBg
          anchors.fill: parent
          color: Color.background
          topLeftRadius: config.tabsPosition === "top" ? 0 : Style.cornerRadius
          topRightRadius: config.tabsPosition === "top" ? 0 : Style.cornerRadius
          bottomLeftRadius: config.tabsPosition === "top" ? Style.cornerRadius : 0
          bottomRightRadius: config.tabsPosition === "top" ? Style.cornerRadius : 0
        }

        Component {
          id: terminalComponent
          TerminalView {
            anchors.fill: parent
            schemeName: root.currentSchemeName
            clipboardBinds: root.currentClipboardBinds
          }
        }
      }

      // Tab Bar (Bottom by default, or Top when configured) - Not affected by opacity setting
      Rectangle {
        id: tabBar
        width: parent.width
        height: 38
        y: config.tabsPosition === "top" ? 0 : parent.height - height
        color: Qt.rgba(Color.background.r * 0.75, Color.background.g * 0.75, Color.background.b * 0.75, 1.0)
        border.width: 0
        topLeftRadius: config.tabsPosition === "top" ? Style.cornerRadius : 0
        topRightRadius: config.tabsPosition === "top" ? Style.cornerRadius : 0
        bottomLeftRadius: config.tabsPosition === "bottom" ? Style.cornerRadius : 0
        bottomRightRadius: config.tabsPosition === "bottom" ? Style.cornerRadius : 0

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

          function ensureTabVisible(tabIndex) {
            if (tabIndex < 0) return
            var itemWidth = Style.space(160) + 4
            var targetX = 6 + (tabIndex * itemWidth)
            if (targetX < tabsFlick.contentX) {
              tabsFlick.contentX = Math.max(0, targetX)
            } else if (targetX + itemWidth > tabsFlick.contentX + tabsFlick.width) {
              tabsFlick.contentX = Math.min(Math.max(0, tabsRow.width - tabsFlick.width), targetX + itemWidth - tabsFlick.width)
            }
          }

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
                width: Style.space(160)
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

                Row {
                  id: tabContentRow
                  anchors.left: parent.left
                  anchors.leftMargin: 10
                  anchors.right: closeBtn.visible ? closeBtn.left : parent.right
                  anchors.rightMargin: 6
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 8

                  Text {
                    id: tabIcon
                    text: root.terminalIcon
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    color: tabItem.isActive ? Color.accent : Color.muted
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: tabLabel
                    text: modelData.title
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: tabItem.isActive
                    color: tabItem.isActive ? Color.foreground : Color.muted
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    width: Math.max(0, tabContentRow.width - tabIcon.width - tabContentRow.spacing)
                  }
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

          // Settings button
          Button {
            text: "⚙"
            tooltipText: "Omaguake Settings"
            fontSize: Style.font.caption
            onClicked: {
              Quickshell.execDetached(["omarchy-shell", "omaguake.bar", "openSettings"])
            }
          }

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

      // Outer Frame Border
      Rectangle {
        id: bgCard
        anchors.fill: parent
        color: "transparent"
        border.color: Color.muted
        border.width: 1
        radius: Style.cornerRadius
        enabled: false
      }
    }
  }
}

