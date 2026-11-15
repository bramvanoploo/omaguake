import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "i18n.js" as I18n

Item {
  id: root

  // Injected by omarchy-shell host
  property var shell: null

  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace("file://", "").replace(/\/$/, "")

  readonly property string barPosition: (root.shell && root.shell.bar && root.shell.bar.position)
    ? String(root.shell.bar.position)
    : "top"
  readonly property bool barHidden: (root.shell && root.shell.bar)
    ? (root.shell.bar.barHidden === true)
    : false
  readonly property int liveBarSize: barHidden
    ? 0
    : ((root.shell && root.shell.bar && root.shell.bar.barSize > 0)
        ? root.shell.bar.barSize
        : ((barPosition === "left" || barPosition === "right") ? Style.bar.sizeVertical : Style.bar.sizeHorizontal))
  readonly property int topBarOffset: (barPosition === "top") ? liveBarSize : 0
  readonly property int bottomBarOffset: (barPosition === "bottom") ? liveBarSize : 0
  readonly property int leftBarOffset: (barPosition === "left") ? liveBarSize : 0
  readonly property int rightBarOffset: (barPosition === "right") ? liveBarSize : 0

  // The configured alignment, resolved to one of the three known values so
  // every consumer (placement, grip liveness, drag math) reads one value.
  readonly property string effectiveAlignment:
    (config && (config.panelAlignment === "left" || config.panelAlignment === "right"))
      ? config.panelAlignment : "center"

  // Horizontal placement of a box of `itemW` inside a `totalW` work area, for
  // the configured panel alignment. Callers pass the bar-aware work area
  // width (availableW already subtracts the left/right bar offsets), so the
  // panel stays inside the work area for any omarchy bar position.
  // `allowOverflow` is for content placement: the terminal grid keeps its
  // press-time size during a shrink drag, so it is deliberately wider than the
  // card and must hang over the free side(s) (negative x, clipped by the
  // container) instead of snapping to the leading edge.
  function alignX(totalW, itemW, allowOverflow) {
    var a = root.effectiveAlignment
    var x
    if (a === "left") return 0
    if (a === "right") x = totalW - itemW
    else x = (totalW - itemW) / 2
    x = Math.round(x)
    return allowOverflow ? x : Math.max(0, x)
  }

  property bool opened: false
  property real slideProgress: 0.0
  property bool blurActive: false
  property bool openSettingsAfterHide: false

  Timer {
    id: openSettingsDelayTimer
    interval: 50
    repeat: false
    onTriggered: {
      Quickshell.execDetached(["omarchy-shell", "omaguake.bar", "openSettings"])
    }
  }

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

  property bool _destroying: false

  Timer {
    id: watcherRestartTimer
    interval: 2000
    repeat: false
    onTriggered: {
      if (!root._destroying && !omarchyThemeWatcher.running) {
        omarchyThemeWatcher.running = true
      }
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
      if (!root._destroying && exitCode !== 127) {
        watcherRestartTimer.restart()
      }
    }
  }

  FileView {
    id: clipboardBindsFile
    // Runtime state under ~/.local/state/omarchy/<plugin-id>/ — never inside
    // the plugin directory itself (Omarchy reloads the plugin on any save
    // there; see ConfigManager.qml).
    path: config.stateDir + "/clipboard_binds.json"
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
  function toggle() {
    if (showAnim.running) {
      hide()
    } else if (hideAnim.running) {
      show()
    } else if (root.opened) {
      hide()
    } else {
      show()
    }
  }

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

  // Dropdown invariant: opening the panel always shows the live prompt.
  // A pane left in tmux copy-mode (scrollback frozen on screen) would
  // otherwise reappear stuck on old output every time the panel opens.
  function cancelActiveTabCopyMode() {
    if (root.currentTabIndex < 0 || root.currentTabIndex >= root.tabs.length) {
      return
    }
    var item = root.tabs[root.currentTabIndex].termItem
    if (item && typeof item.cancelTmuxCopyMode === "function") {
      item.cancelTmuxCopyMode()
    }
  }

  onCurrentTabIndexChanged: {
    root.updateTerminalVisibility()
    Qt.callLater(function() { root.refreshActiveTerminal() })
  }

  function show() {
    if (root.tabs.length === 0) {
      root.createTab()
    }
    root.openSettingsAfterHide = false
    openSettingsDelayTimer.stop()
    root.opened = true
    root.blurActive = false
    hideAnim.stop()
    showAnim.start()
    root.updateTerminalVisibility()
    Qt.callLater(function() { root.refreshActiveTerminal() })
    Qt.callLater(function() { root.cancelActiveTabCopyMode() })
  }

  function hide() {
    if (!root.opened && !showAnim.running) return
    root.blurActive = false
    showAnim.stop()
    hideAnim.start()
  }

  property var terminalComponent: null

  function getTerminalComponent() {
    if (!terminalComponent || terminalComponent.status === Component.Error) {
      terminalComponent = Qt.createComponent("TerminalView.qml")
    }
    return terminalComponent
  }

  function createTab(specifiedId) {
    if (specifiedId !== undefined && specifiedId !== null) {
      var checkId = Number(specifiedId)
      for (var t = 0; t < tabs.length; t++) {
        if (tabs[t].id === checkId) return
      }
    }
    var newId = (specifiedId !== undefined && specifiedId !== null) ? Number(specifiedId) : nextTabId++
    if (!Number.isFinite(newId)) {
      // Non-numeric session ids (stray sessions on the tmux socket) would
      // otherwise produce "omaguake_tab_NaN" sessions on restore.
      console.warn("Ignoring invalid tab id from restore: " + specifiedId)
      newId = nextTabId++
    }
    if (newId >= nextTabId) {
      nextTabId = newId + 1
    }
    var comp = root.getTerminalComponent()
    if (!comp || comp.status === Component.Error) {
      console.warn("TerminalView component unavailable: " + (comp ? comp.errorString() : "null"))
      return
    }
    var term = comp.createObject(terminalArea, {
      tabId: String(newId),
      schemeName: root.currentSchemeName,
      clipboardBinds: root.currentClipboardBinds,
      toggleKeybinding: config.keybinding || "",
      cardOpacity: container.cardOpacity,
      visible: false,
      activeTab: false
    })

    if (!term) {
      console.warn("Failed to create TerminalView object for tab " + newId)
      return
    }
    term.anchors.fill = terminalArea

    term.titleUpdated.connect(function(newTitle) {
      root.updateTabTitleById(newId, newTitle)
    })
    term.commandUpdated.connect(function(cmdText) {
      root.updateLastCommandById(newId, cmdText)
    })
    term.processExited.connect(function(code) {
      // A process exit during plugin/shell teardown is qmltermwidget killing
      // the tmux attach client, not the pane closing; killing the tmux
      // session here would destroy persisted tabs on every reload.
      if (root._destroying) return
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
    term.toggleRequested.connect(function() {
      root.toggle()
    })
    term.increaseHeightRequested.connect(function() {
      root.increaseHeight()
    })
    term.decreaseHeightRequested.connect(function() {
      root.decreaseHeight()
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

    if (term && typeof term.reloadColorScheme === "function") {
      term.reloadColorScheme(root.currentSchemeName)
    }

    Qt.callLater(function() {
      if (term && typeof term.reloadColorScheme === "function") {
        term.reloadColorScheme(root.currentSchemeName)
      }
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
    if (tabToClose) {
      Quickshell.execDetached([root.pluginDir + "/scripts/session-manager.py", "kill", "omaguake_tab_" + tabToClose.id])
      if (tabToClose.termItem) {
        try {
          tabToClose.termItem.visible = false
          tabToClose.termItem.activeTab = false
          tabToClose.termItem.destroy()
        } catch(e) {}
      }
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
    onFinished: {
      if (root.opened) {
        root.blurActive = true
      }
      root.refreshActiveTerminal()
    }
  }

  NumberAnimation {
    id: hideAnim
    target: root
    property: "slideProgress"
    to: 0.0
    duration: 250
    easing.type: Easing.OutCubic
    onFinished: {
      root.opened = false
      root.blurActive = false
      root.updateTerminalVisibility()
      if (root.openSettingsAfterHide) {
        root.openSettingsAfterHide = false
        openSettingsDelayTimer.restart()
      }
    }
  }

  // Hyprland Global Shortcuts
  GlobalShortcut {
    appid: "bramvanoploo.omaguake"
    name: "toggle"
    description: "Toggle OmaGuake dropdown terminal"
    onPressed: root.toggle()
  }

  GlobalShortcut {
    appid: "bramvanoploo.omaguake"
    name: "show"
    description: "Show OmaGuake dropdown terminal"
    onPressed: root.show()
  }

  GlobalShortcut {
    appid: "bramvanoploo.omaguake"
    name: "hide"
    description: "Hide OmaGuake dropdown terminal"
    onPressed: root.hide()
  }

  function adjustHeightPercent(delta) {
    if (!root.opened) return
    var current = config.heightPercent !== undefined ? config.heightPercent : 50
    // Keep the 5% step but preserve fractional values left by edge dragging
    // (rounding to the 5-grid here would visibly snap a finely dragged panel).
    var next = Math.max(20, Math.min(100, Math.round((current + delta) * 10) / 10))
    if (next !== current) {
      config.saveSettings({ heightPercent: next })
      Qt.callLater(function() { root.refreshActiveTerminal() })
    }
  }

  function increaseHeight() {
    adjustHeightPercent(5)
  }

  function decreaseHeight() {
    adjustHeightPercent(-5)
  }

  // -------------------------------------------------------------------------
  // Edge drag-to-resize. Grabbing the bottom edge adjusts height, grabbing a
  // side edge adjusts width: symmetrically while the panel is centered, or
  // from the free edge only when it is aligned left/right in the work area. While
  // dragging, the panel follows a fractional live percent through a frame-
  // rate pump (no file writes, no config churn); the exact final value is
  // persisted once on release - into the state dir, not the watched plugin
  // dir, so resizing never reloads the plugin.
  //
  // The width grips sit exactly over TerminalView's decorative 20px side
  // margin strips (never over terminal text) and span only the terminal area,
  // so tab-bar buttons stay clickable. A plain click on a width grip (no
  // movement) keeps the margin strips' behavior: leave tmux copy-mode.
  // -------------------------------------------------------------------------
  property bool resizingWidth: false
  property bool resizingHeight: false
  property bool _resizeMoved: false
  property real _resizeStartX: 0
  property real _resizeStartY: 0
  // Pixel size frozen at press; the terminal grid keeps this and is only
  // clipped by the animating card, so content never deforms mid-drag.
  property real _dragStartW: 0
  property real _dragStartH: 0
  property real _dragTermW: 0
  property real _dragTermH: 0
  // Latest pointer-derived target size and the eased size actually shown.
  // The eased values follow the target through NumberAnimation Behaviors,
  // exactly how Hyprland eases a window while its border is dragged.
  property real _dragTargetW: 0
  property real _dragTargetH: 0

  // Pointer position in window (surface-local) coordinates. The MouseEvent
  // wrapper of this Qt build does not expose sceneX/sceneY (reading them
  // yields undefined, which made every drag compute NaN and collapse the
  // panel to its minimum), so map the item-relative x/y through the scene
  // graph to the window root instead. During a drag the surface geometry is
  // fixed, so these are stable absolute reference points even though the
  // card is scaled under the cursor (the implicit pointer grab keeps motion
  // events delivered while the button is held, even outside the grip).
  function _dragPoint(item, mouse) {
    try {
      var p = item.mapToItem(null, mouse.x, mouse.y)
      if (p && isFinite(p.x) && isFinite(p.y)) return p
    } catch (e) {
      console.warn("omaguake: drag pointer mapping failed")
    }
    return null
  }

  // Pointer events arrive at the mouse polling rate (125Hz+); handlers only
  // record the latest target size and this single-shot pump applies it once
  // per frame, where the Behaviors ease it smoothly.
  Timer {
    id: resizeApplyTimer
    interval: 16
    repeat: false
    onTriggered: root._pumpResize()
  }

  function _pumpResize() {
    if (resizingHeight) {
      if (Math.abs(root._dragTargetH - panelWindow._dragVisualH) > 0.25) {
        panelWindow._dragVisualH = root._dragTargetH
        root._resizeMoved = true
      }
      resizeApplyTimer.restart()
    }
    if (resizingWidth) {
      if (Math.abs(root._dragTargetW - panelWindow._dragVisualW) > 0.25) {
        panelWindow._dragVisualW = root._dragTargetW
        root._resizeMoved = true
      }
      resizeApplyTimer.restart()
    }
  }

  function beginHeightDrag(item, mouse) {
    var p = _dragPoint(item, mouse)
    if (!p) return
    _resizeMoved = false
    _dragStartH = panelWindow.panelH
    _dragStartW = panelWindow.panelW
    _dragTermW = terminalArea.width
    _dragTermH = terminalArea.height
    _dragTargetH = _dragStartH
    // Seed the eased sizes before entering drag mode: the Behaviors are
    // disabled while not dragging, so they land instantly at the current
    // true size instead of animating up from zero (which showed as a
    // visible size glitch on press).
    panelWindow._dragVisualW = _dragStartW
    panelWindow._dragVisualH = _dragStartH
    _resizeStartY = p.y
    resizingHeight = true
  }

  function updateHeightDrag(item, mouse) {
    if (!resizingHeight) return
    var p = _dragPoint(item, mouse)
    if (!p) return
    var availH = panelWindow.availableH
    if (availH <= 0) return
    // The surface origin never moves for a height drag (top margin fixed),
    // so the pointer delta maps 1:1 onto the card height.
    var h = _dragStartH + (p.y - _resizeStartY)
    h = Math.max(Math.round(0.2 * availH), Math.min(availH, h))
    if (!isFinite(h)) return
    _dragTargetH = h
    if (!resizeApplyTimer.running) resizeApplyTimer.start()
  }

  function endHeightDrag() {
    if (!resizingHeight) return
    resizingHeight = false
    var moved = _resizeMoved
    // Commit the exact pointer target, not the mid-animation visual.
    var finalSize = (_dragTargetH > 0 ? _dragTargetH : _dragStartH)
    // Leaving drag mode (resizingHeight=false above) disables the Behaviors,
    // so resetting the visual size is instant; the config commit below then
    // resizes the window to the size the scaled card was already showing -
    // the GPU scale and the real geometry agree, so nothing jumps.
    panelWindow._dragVisualH = 0
    _dragTargetH = 0
    if (moved) {
      var pct = finalSize / panelWindow.availableH * 100.0
      pct = Math.max(20, Math.min(100, pct))
      pct = Math.round(pct * 100) / 100
      config.heightPercent = pct
      config.saveSettings({ heightPercent: pct })
      Qt.callLater(function() { root.refreshActiveTerminal() })
    }
  }

  // side: -1 = left grip (drag left to widen), +1 = right grip.
  // A centered panel grows from both edges, so both grips are live and the
  // width changes at twice the pointer delta (each half-edge moves by half of
  // it, which keeps the grabbed edge glued to the cursor). When the panel is
  // aligned left or right, the edge on that side is pinned to the work-area
  // edge: that grip stops resizing and only the free edge drags, 1:1.
  function isWidthGripLive(side) {
    var a = root.effectiveAlignment
    if (a === "left") return side === 1
    if (a === "right") return side === -1
    return true
  }

  function beginWidthDrag(item, side, mouse) {
    if (!isWidthGripLive(side)) {
      // Pinned edge: no resize, but keep the margin strip behavior of a plain
      // click (drop tmux copy-mode), same as endWidthDrag's no-move case.
      root.cancelActiveTabCopyMode()
      return
    }
    var p = _dragPoint(item, mouse)
    if (!p) return
    _resizeMoved = false
    _dragStartW = panelWindow.panelW
    _dragStartH = panelWindow.panelH
    _dragTermW = terminalArea.width
    _dragTermH = terminalArea.height
    _dragTargetW = _dragStartW
    panelWindow._dragVisualW = _dragStartW
    panelWindow._dragVisualH = _dragStartH
    _resizeStartX = p.x
    resizingWidth = true
  }

  function updateWidthDrag(item, side, mouse) {
    if (!resizingWidth) return
    var p = _dragPoint(item, mouse)
    if (!p) return
    var availW = panelWindow.availableW
    if (availW <= 0) return
    // The surface never moves while the panel is open, so the mapped
    // pointer delta is already the true cursor movement.
    var cursorDelta = p.x - _resizeStartX
    // Pointer-delta multiplier, read per event rather than snapshotted at
    // press: a centered card grows from both edges (2x, the grabbed edge stays
    // glued to the cursor), a left-/right-aligned card has one edge pinned to
    // the work-area edge, so its free edge follows the pointer 1:1. Reading it
    // live keeps the grab math in step with the placement, which also follows
    // the setting when it changes mid-drag (external settings.json edit).
    var factor = (root.effectiveAlignment === "center") ? 2.0 : 1.0
    var w = _dragStartW + side * factor * cursorDelta
    w = Math.max(Math.round(0.2 * availW), Math.min(availW, w))
    if (!isFinite(w)) return
    _dragTargetW = w
    if (!resizeApplyTimer.running) resizeApplyTimer.start()
  }

  function endWidthDrag() {
    if (!resizingWidth) return
    resizingWidth = false
    var moved = _resizeMoved
    var finalSize = (_dragTargetW > 0 ? _dragTargetW : _dragStartW)
    panelWindow._dragVisualW = 0
    _dragTargetW = 0
    if (moved) {
      var pct = finalSize / panelWindow.availableW * 100.0
      pct = Math.max(20, Math.min(100, pct))
      pct = Math.round(pct * 100) / 100
      config.widthPercent = pct
      config.saveSettings({ widthPercent: pct })
      Qt.callLater(function() { root.refreshActiveTerminal() })
    } else {
      // Click without drag on the side margin: behave like the margin strip
      // click in TerminalView (drop tmux copy-mode so keystrokes aren't
      // swallowed by a stuck copy-mode state).
      root.cancelActiveTabCopyMode()
    }
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
    function increaseHeight(): void { root.increaseHeight() }
    function decreaseHeight(): void { root.decreaseHeight() }
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
    function increaseHeight(): void { root.increaseHeight() }
    function decreaseHeight(): void { root.decreaseHeight() }
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
      themeSyncProc.command = [root.pluginDir + "/scripts/sync-theme.py"]
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

  Process {
    id: sessionRestoreProc
    command: [root.pluginDir + "/scripts/session-manager.py", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        var restored = false
        if (raw.length > 0) {
          try {
            var list = JSON.parse(raw)
            if (list && list.length > 0) {
              for (var i = 0; i < list.length; i++) {
                var s = list[i]
                var tid = s.id !== undefined ? s.id : (i + 1)
                root.createTab(tid)
              }
              restored = true
            }
          } catch(e) {}
        }
        if (!restored && root.tabs.length === 0) {
          root.createTab()
        }
      }
    }
  }

  Component.onCompleted: {
    sessionRestoreProc.running = true
    root.reloadTheme()
    root.reloadClipboardBinds()
  }

  Component.onDestruction: {
    root._destroying = true
    watcherRestartTimer.stop()
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
      for (var i = 0; i < root.tabs.length; i++) {
        if (root.tabs[i].termItem) {
          root.tabs[i].termItem.cardOpacity = container.cardOpacity
        }
      }
    }
    function onKeybindingChanged() {
      for (var i = 0; i < root.tabs.length; i++) {
        if (root.tabs[i].termItem) {
          root.tabs[i].termItem.toggleKeybinding = config.keybinding || ""
        }
      }
    }
    function onLanguageChanged() {
      I18n.setLanguageOverride(config.language)
    }
  }

  property bool focusPrimed: false

  onOpenedChanged: {
    if (opened) {
      root.notifyTabsRetheme()
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

  // Dedicated blur surface: maps only when settled, unmaps immediately on hide.
  // It is the only surface carrying blur (the Hyprland layer rule written by
  // scripts/conflict-checker.py matches namespace "omaguake", and the panel
  // surface's namespace deliberately does not match it - otherwise a resized
  // blur surface would drag blur geometry along with configure churn).
  PanelWindow {
    id: blurWindow
    visible: root.blurActive && root.opened
    anchors { top: true; left: true; right: true }
    margins {
      top: root.topBarOffset
      // Tracks the card's horizontal placement (panel alignment aware) so the
      // blur region sits exactly under the card, not under a centered rect.
      left: root.leftBarOffset + panelWindow._cardX
      right: root.rightBarOffset + Math.max(0, Math.round(panelWindow.availableW - panelWindow._cardW - panelWindow._cardX))
    }
    color: "transparent"
    surfaceFormat.opaque: false

    // Exact card extent (eased visual size during a drag): the blur region
    // is this surface's extent, so it tracks the card frame by frame.
    implicitHeight: Math.max(1, Math.round(panelWindow._cardH))
    implicitWidth: Math.max(1, Math.round(panelWindow._cardW))

    WlrLayershell.namespace: "omaguake"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
      x: 0
      y: 0
      width: 0
      height: 0
    }
  }

  PanelWindow {
    id: panelWindow
    visible: root.slideProgress > 0.001 || root.opened
    anchors { top: true; left: true; right: true }
    // Fixed surface geometry while visible: never resized, so the
    // compositor never re-configures (or stretches old buffers for) the
    // surface during open, drag or release. The card itself is plain QML
    // layout inside - resizing it costs nothing at the Wayland level.
    margins {
      top: root.topBarOffset
      left: root.leftBarOffset
      right: root.rightBarOffset
    }
    color: "transparent"
    surfaceFormat.opaque: false

    readonly property real screenW: screen ? screen.width : 1920
    readonly property real screenH: screen ? screen.height : 1080
    readonly property real availableW: Math.max(100, screenW - root.leftBarOffset - root.rightBarOffset)
    readonly property real availableH: Math.max(100, screenH - root.topBarOffset - root.bottomBarOffset)
    readonly property real panelH: Math.round(availableH * (Math.max(20, Math.min(100, config.heightPercent)) / 100.0))
    readonly property real panelW: Math.round(availableW * (Math.max(20, Math.min(100, config.widthPercent !== undefined ? config.widthPercent : 100)) / 100.0))

    // Hyprland-style edge drag: while dragging, only QML items move - the
    // card eases toward the pointer target through the Behaviors below
    // (like Hyprland easing a window frame), while the surface stays put.
    // _dragVisual* is the eased drag size; the card rect is _cardW/_cardH,
    // which mask and blur follow each frame.
    readonly property bool _dragMode: root.resizingWidth || root.resizingHeight
    property real _dragVisualW: 0
    property real _dragVisualH: 0
    Behavior on _dragVisualW {
      enabled: panelWindow._dragMode
      NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
    }
    Behavior on _dragVisualH {
      enabled: panelWindow._dragMode
      NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
    }
    readonly property real _cardW: _dragMode && _dragVisualW > 0 ? Math.round(_dragVisualW) : panelW
    readonly property real _cardH: _dragMode && _dragVisualH > 0 ? Math.round(_dragVisualH) : panelH
    // Card placement inside the (bar-aware) work area for the current panel
    // alignment; the mask, the card item and the blur surface all follow it.
    readonly property real _cardX: root.alignX(availableW, _cardW)

    implicitHeight: availableH
    implicitWidth: availableW

    // Input region covers only the card, never the transparent area around
    // it, so clicks beside the panel fall through to the desktop.
    mask: Region {
      x: panelWindow._cardX
      y: 0
      width: Math.max(0, Math.round(panelWindow._cardW))
      height: Math.max(0, Math.round(panelWindow._cardH * root.slideProgress))
    }

    // Deliberately NOT matching the "omaguake" substring of the plugin's
    // Hyprland blur layer rule (see blurWindow above): this surface is full
    // working-area sized, so blurring it would blur the whole screen.
    WlrLayershell.namespace: "guake-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (root.opened && !hideAnim.running)
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
      active: root.opened && root.focusPrimed && config.autoHideOnFocusLoss && !hideAnim.running
      windows: [panelWindow]
      onCleared: {
        if (root.opened && config.autoHideOnFocusLoss && !hideAnim.running) {
          root.hide()
        }
      }
    }

    // Sliding container item = the card. It carries the eased drag size
    // while the surface stays fixed: the card, borders and tab bar
    // relayout at true pixel sizes (nothing is squashed), and the terminal
    // keeps its press-time cell grid - clipped, never deformed - reflowing
    // once on release. Relayout inside a fixed surface is cheap: no
    // configure, no buffer realloc.
    Item {
      id: container
      width: panelWindow._cardW
      height: panelWindow._cardH
      x: panelWindow._cardX
      y: Math.round((root.slideProgress - 1.0) * height)
      clip: true

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

      // Terminal Content Area (Background-only opacity shader keeps text 100% opaque)
      Item {
        id: terminalArea
        // During an edge drag the grid keeps its press-time size (placed in
        // the animating card by the panel alignment, clipped by the container
        // when the card is smaller) so text never deforms or reflows mid-drag.
        // Overflow is allowed: when shrinking, the grid is wider than the card
        // and hangs over the free side(s), exactly as a centered panel did
        // before alignment existed (and a right-aligned one hangs left).
        width: panelWindow._dragMode ? Math.round(root._dragTermW) : parent.width
        height: panelWindow._dragMode ? Math.round(root._dragTermH) : parent.height - tabBar.height
        x: panelWindow._dragMode ? root.alignX(parent.width, width, true) : 0
        y: config.tabsPosition === "top" ? tabBar.height : 0
        clip: true
        layer.enabled: container.cardOpacity < 0.999
        layer.effect: ShaderEffect {
          property color bgColor: Color.background
          property real bgOpacity: container.cardOpacity
          fragmentShader: Qt.resolvedUrl("bg_opacity.frag.qsb")
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
                    textFormat: Text.PlainText
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    color: tabItem.isActive ? Color.accent : Color.muted
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: tabLabel
                    text: modelData.title
                    textFormat: Text.PlainText
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

          // Pin button: toggles "Auto-hide on focus loss".
          // Accent-colored (same as active tab border) = pinned = auto-hide disabled.
          Button {
            readonly property bool pinned: !config.autoHideOnFocusLoss
            iconText: "\uf276" // pin (diagonal pushpin)
            iconSize: Style.font.caption
            foreground: pinned ? Color.accent : Color.foreground
            tooltipText: { var _ = config.language; return I18n.t("pin_tooltip") + (pinned ? " " + I18n.t("pin_pinned") : "") }
            onClicked: config.saveSettings({ autoHideOnFocusLoss: !config.autoHideOnFocusLoss })
          }

          // Settings button
          Button {
            text: "⚙"
            tooltipText: { var _ = config.language; return I18n.t("open_settings") }
            fontSize: Style.font.caption
            onClicked: {
              if (root.opened || showAnim.running || hideAnim.running) {
                root.openSettingsAfterHide = true
                root.hide()
              } else {
                Quickshell.execDetached(["omarchy-shell", "omaguake.bar", "openSettings"])
              }
            }
          }

          // Slide Up / Minimize button
          Button {
            text: "▲"
            tooltipText: { var _ = config.language; return I18n.t("hide_terminal", { chord: config.keybinding || "" }) }
            fontSize: Style.font.caption
            onClicked: root.hide()
          }

          // Pinned "+" button to open more tabs
          Button {
            id: newTabBtn
            text: "+"
            tooltipText: { var _ = config.language; return I18n.t("open_new_tab") }
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

      // --- Drag-to-resize edge grips (see begin/update/endDrag functions) ---
      // Accent edge appears on hover as the grab affordance. When the panel is
      // aligned left or right, the edge pinned to the work-area boundary is
      // not a resize target, so its grip drops the accent and resize cursor
      // (it keeps the plain click behavior of the margin strip).
      MouseArea {
        id: widthGripLeft
        z: 20
        hoverEnabled: true
        x: 0
        y: config.tabsPosition === "top" ? tabBar.height : 0
        width: 20
        height: Math.max(0, parent.height - tabBar.height)
        cursorShape: root.isWidthGripLive(-1) ? Qt.SizeHorCursor : Qt.ArrowCursor
        onPressed: function(mouse) { root.beginWidthDrag(widthGripLeft, -1, mouse) }
        onPositionChanged: function(mouse) { root.updateWidthDrag(widthGripLeft, -1, mouse) }
        onReleased: root.endWidthDrag()
        onCanceled: root.endWidthDrag()

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 2
          color: Color.accent
          opacity: 0.75
          visible: root.isWidthGripLive(-1) && (widthGripLeft.containsMouse || widthGripLeft.pressed)
        }
      }

      MouseArea {
        id: widthGripRight
        z: 20
        hoverEnabled: true
        x: parent.width - 20
        y: config.tabsPosition === "top" ? tabBar.height : 0
        width: 20
        height: Math.max(0, parent.height - tabBar.height)
        cursorShape: root.isWidthGripLive(1) ? Qt.SizeHorCursor : Qt.ArrowCursor
        onPressed: function(mouse) { root.beginWidthDrag(widthGripRight, 1, mouse) }
        onPositionChanged: function(mouse) { root.updateWidthDrag(widthGripRight, 1, mouse) }
        onReleased: root.endWidthDrag()
        onCanceled: root.endWidthDrag()

        Rectangle {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 2
          color: Color.accent
          opacity: 0.75
          visible: root.isWidthGripLive(1) && (widthGripRight.containsMouse || widthGripRight.pressed)
        }
      }

      // Bottom edge: 6px over the tab bar's vertical padding when the bar is
      // at the bottom (default), over the terminal's last text line when the
      // bar is at the top.
      MouseArea {
        id: heightGripBottom
        z: 20
        hoverEnabled: true
        x: 0
        y: parent.height - 6
        width: parent.width
        height: 6
        cursorShape: Qt.SizeVerCursor
        onPressed: function(mouse) { root.beginHeightDrag(heightGripBottom, mouse) }
        onPositionChanged: function(mouse) { root.updateHeightDrag(heightGripBottom, mouse) }
        onReleased: root.endHeightDrag()
        onCanceled: root.endHeightDrag()

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 2
          color: Color.accent
          opacity: 0.75
          visible: heightGripBottom.containsMouse || heightGripBottom.pressed
        }
      }
    }
  }
}

