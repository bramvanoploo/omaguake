import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import QMLTermWidget

Item {
  id: root

  property string tabId: ""
  property string currentTitle: "bash"
  property bool activeTab: false

  property string lastCommand: ""

  signal titleUpdated(string newTitle)
  signal commandUpdated(string commandText)
  signal processExited(int exitCode)

  signal newTabRequested()
  signal closeTabRequested()
  signal nextTabRequested()
  signal previousTabRequested()
  signal switchTabNumberRequested(int tabNumber)
  signal toggleRequested()

  property string toggleKeybinding: ""
  property string schemeName: "Omaguake"
  property real cardOpacity: 1.0

  onCardOpacityChanged: {
    root.reloadColorScheme(root.schemeName)
  }

  onSchemeNameChanged: {
    if (terminal && schemeName.length > 0) {
      root.reloadColorScheme(schemeName)
    }
  }


  function queryPaneState() {
    if (!paneQueryProc.running) {
      paneQueryProc.command = [root.pluginDir + "/scripts/session-manager.py", "query", "omaguake_tab_" + (root.tabId || "1")]
      paneQueryProc.running = true
    }
  }

  Process {
    id: paneQueryProc
    command: [root.pluginDir + "/scripts/session-manager.py", "query", "omaguake_tab_" + (root.tabId || "1")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw.length > 0) {
          try {
            var data = JSON.parse(raw)
            if (data) {
              if (data.cwd) {
                root.titleUpdated(data.cwd)
              }
              if (data.command && data.command !== "bash" && data.command !== "sh" && data.command !== "zsh" && data.command !== "fish" && data.command !== "tmux") {
                if (!root.lastCommand || root.lastCommand !== data.command) {
                  root.lastCommand = data.command
                  root.commandUpdated(data.command)
                }
              }
            }
          } catch(e) {}
        }
      }
    }
  }

  Timer {
    id: immediateQueryTimer
    interval: 50
    repeat: false
    onTriggered: root.queryPaneState()
  }

  // Poll tmux pane state at a relaxed cadence, only while this tab is the
  // visible/active one. A 500ms subprocess spawn per tab is wasteful; titles
  // update on <Enter> via immediateQueryTimer, so a slower poll suffices.
  Timer {
    id: procCheckTimer
    interval: 1500
    repeat: true
    running: root.activeTab && root.visible
    onTriggered: root.queryPaneState()
  }

  property var clipboardBinds: null

  function matchKeyBind(event, bindList) {
    if (!bindList || !bindList.length) return false
    for (var i = 0; i < bindList.length; i++) {
      var item = bindList[i]
      var modmask = item.modmask || 0
      var keyStr = String(item.key || "").trim().toUpperCase()

      // Convert modmask bits: 64 -> Meta, 4 -> Control, 1 -> Shift, 8 -> Alt
      var expectedMods = 0
      if (modmask & 64) expectedMods |= Qt.MetaModifier
      if (modmask & 4)  expectedMods |= Qt.ControlModifier
      if (modmask & 1)  expectedMods |= Qt.ShiftModifier
      if (modmask & 8)  expectedMods |= Qt.AltModifier

      var activeMods = event.modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier)
      if (activeMods !== expectedMods) continue

      var matchesKey = false
      if (keyStr.length === 1 && keyStr >= "A" && keyStr <= "Z") {
        matchesKey = (event.key === (Qt.Key_A + (keyStr.charCodeAt(0) - 65)))
      } else if (keyStr.length === 1 && keyStr >= "0" && keyStr <= "9") {
        matchesKey = (event.key === (Qt.Key_0 + (keyStr.charCodeAt(0) - 48)))
      } else if (keyStr === "INSERT") {
        matchesKey = (event.key === Qt.Key_Insert)
      } else if (keyStr === "DELETE") {
        matchesKey = (event.key === Qt.Key_Delete)
      } else if (keyStr === "RETURN" || keyStr === "ENTER") {
        matchesKey = (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
      } else if (keyStr === "SPACE") {
        matchesKey = (event.key === Qt.Key_Space)
      } else if (keyStr === "BACKSPACE") {
        matchesKey = (event.key === Qt.Key_Backspace)
      }

      if (matchesKey) return true
    }
    return false
  }

  function matchChord(event, chordStr) {
    if (!chordStr || !chordStr.trim()) return false
    var parts = chordStr.split("+").map(function(s) { return s.trim().toUpperCase() })
    var expectedMods = 0
    var expectedKeyStr = ""
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i]
      if (p === "CTRL" || p === "CONTROL") expectedMods |= Qt.ControlModifier
      else if (p === "ALT") expectedMods |= Qt.AltModifier
      else if (p === "SUPER" || p === "META") expectedMods |= Qt.MetaModifier
      else if (p === "SHIFT") expectedMods |= Qt.ShiftModifier
      else expectedKeyStr = p
    }

    var activeMods = event.modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier)
    if (activeMods !== expectedMods) return false

    var k = event.key
    if (expectedKeyStr === "SPACE") return (k === Qt.Key_Space)
    if (expectedKeyStr === "GRAVE" || expectedKeyStr === "`" || expectedKeyStr === "~") return (k === Qt.Key_QuoteLeft || k === Qt.Key_AsciiTilde)
    if (expectedKeyStr === "RETURN" || expectedKeyStr === "ENTER") return (k === Qt.Key_Return || k === Qt.Key_Enter)
    if (expectedKeyStr === "TAB") return (k === Qt.Key_Tab || k === Qt.Key_Backtab)
    if (expectedKeyStr === "ESCAPE" || expectedKeyStr === "ESC") return (k === Qt.Key_Escape)
    if (expectedKeyStr === "BACKSPACE") return (k === Qt.Key_Backspace)
    if (expectedKeyStr.indexOf("F") === 0 && expectedKeyStr.length >= 2) {
      var fNum = parseInt(expectedKeyStr.slice(1), 10)
      if (fNum >= 1 && fNum <= 12) return (k === (Qt.Key_F1 + fNum - 1))
    }
    if (expectedKeyStr.length === 1 && expectedKeyStr >= "A" && expectedKeyStr <= "Z") {
      return (k === (Qt.Key_A + (expectedKeyStr.charCodeAt(0) - 65)))
    }
    if (expectedKeyStr.length === 1 && expectedKeyStr >= "0" && expectedKeyStr <= "9") {
      return (k === (Qt.Key_0 + (expectedKeyStr.charCodeAt(0) - 48)))
    }
    if (event.text && event.text.toUpperCase() === expectedKeyStr) return true
    return false
  }

  function checkIsCopy(event) {
    if (clipboardBinds && clipboardBinds.copy && matchKeyBind(event, clipboardBinds.copy)) {
      return true
    }
    // Standard terminal fallbacks: Super+C, Ctrl+Shift+C, Ctrl+Insert
    if ((event.modifiers & Qt.MetaModifier) && event.key === Qt.Key_C) return true
    if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_C) return true
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Insert) return true
    return false
  }

  function checkIsPaste(event) {
    if (clipboardBinds && clipboardBinds.paste && matchKeyBind(event, clipboardBinds.paste)) {
      return true
    }
    // Standard terminal fallbacks: Super+V, Ctrl+Shift+V, Shift+Insert
    if ((event.modifiers & Qt.MetaModifier) && event.key === Qt.Key_V) return true
    if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_V) return true
    if ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Insert) return true
    return false
  }

  Process {
    id: pasteProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var str = String(text || "")
        if (str.length > 0) {
          if (terminal && typeof terminal.bracketedPasteMode === "function" && terminal.bracketedPasteMode()) {
            termSession.sendText("\u001b[200~" + str + "\u001b[201~")
          } else {
            termSession.sendText(str)
          }
        } else {
          terminal.pasteClipboard()
        }
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        terminal.pasteClipboard()
      }
    }
  }

  function doPaste() {
    var sessionName = "omaguake_tab_" + (root.tabId || "1")
    Quickshell.execDetached([
      "tmux", "-L", "omaguake", "send-keys", "-t", sessionName, "-X", "cancel"
    ])
    if (!pasteProc.running) {
      pasteProc.command = ["wl-paste", "--no-newline"]
      pasteProc.running = true
    } else {
      terminal.pasteClipboard()
    }
  }

  property string pluginDir: String(Qt.resolvedUrl(".")).replace("file://", "").replace(/\/$/, "")

  Rectangle {
    id: leftMarginStrip
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 20
    color: Color.background
  }

  MouseArea {
    anchors.fill: leftMarginStrip
    onClicked: terminal.forceActiveFocus()
  }

  Rectangle {
    id: rightMarginStrip
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 20
    color: Color.background
  }

  MouseArea {
    anchors.fill: rightMarginStrip
    onClicked: terminal.forceActiveFocus()
  }

  QMLTermWidget {
    id: terminal
    anchors.left: leftMarginStrip.right
    anchors.right: rightMarginStrip.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    fillColor: "transparent"
    focus: root.activeTab
    Keys.priority: Keys.BeforeItem

    colorScheme: "DarkPastels"
    font.family: (Style.resolvedFontFamily && Style.resolvedFontFamily !== "monospace")
      ? Style.resolvedFontFamily
      : "JetBrainsMono Nerd Font"
    font.pointSize: 10

    session: QMLTermSession {
      id: termSession
      initialWorkingDirectory: Quickshell.env("HOME") || "."

      onFinished: {
        root.processExited(0)
      }
    }

    Keys.onPressed: function(event) {
      if (root.toggleKeybinding && root.matchChord(event, root.toggleKeybinding)) {
        root.toggleRequested()
        event.accepted = true
        return
      }

      var isCopy = root.checkIsCopy(event)
      var isPaste = root.checkIsPaste(event)

      if (isCopy) {
        terminal.copyClipboard()
        var sessionName = "omaguake_tab_" + (root.tabId || "1")
        Quickshell.execDetached([
          "tmux", "-L", "omaguake", "send-keys", "-t", sessionName,
          "-X", "copy-pipe-and-cancel", "wl-copy"
        ])
        event.accepted = true
        return
      } else if (isPaste) {
        root.doPaste()
        event.accepted = true
        return
      }

      // Tab Management Shortcuts
      if (event.modifiers & Qt.ControlModifier) {
        if (!(event.modifiers & (Qt.AltModifier | Qt.MetaModifier))) {
          if (event.key === Qt.Key_T && !(event.modifiers & Qt.ShiftModifier)) {
            root.newTabRequested()
            event.accepted = true
            return
          } else if (event.key === Qt.Key_W && !(event.modifiers & Qt.ShiftModifier)) {
            root.closeTabRequested()
            event.accepted = true
            return
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            if (event.modifiers & Qt.ShiftModifier || event.key === Qt.Key_Backtab) {
              root.previousTabRequested()
            } else {
              root.nextTabRequested()
            }
            event.accepted = true
            return
          } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && !(event.modifiers & Qt.ShiftModifier)) {
            var tabNum = (event.key - Qt.Key_1) + 1
            root.switchTabNumberRequested(tabNum)
            event.accepted = true
            return
          }
        }
      }

      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        immediateQueryTimer.restart()
      }
    }

    Component.onCompleted: {
      var wrapperScript = root.pluginDir + "/scripts/tmux-session.sh"
      var sessionName = "omaguake_tab_" + (root.tabId || "1")
      if (typeof termSession.setKeyBindings === "function") {
        termSession.setKeyBindings("default")
      }
      if (typeof termSession.setShellProgram === "function") {
        termSession.setShellProgram(wrapperScript)
      }
      if (typeof termSession.setArgs === "function") {
        termSession.setArgs([sessionName, "attach"])
      }
      termSession.startShellProgram()
      root.reloadColorScheme(root.schemeName)
      immediateQueryTimer.restart()
      if (root.activeTab) {
        root.refreshTerminal()
      }
    }
  }

  // MouseArea removed to prevent deselection on click

  function refreshTerminal() {
    if (terminal) {
      try {
        if (typeof terminal.updateImage === "function") {
          terminal.updateImage()
        }
      } catch(e) {}
      try {
        if (typeof terminal.updateCursor === "function") {
          terminal.updateCursor()
        }
      } catch(e) {}
      try {
        if (typeof terminal.update === "function") {
          terminal.update()
        }
      } catch(e) {}
      if (root.activeTab) {
        terminal.forceActiveFocus()
      }
    }
  }

  function reloadColorScheme(newScheme) {
    if (newScheme && newScheme.length > 0) {
      root.schemeName = newScheme
    }
    if (terminal) {
      if (typeof terminal.setBackgroundColor === "function" && Color.background) {
        terminal.setBackgroundColor(Color.background)
      }
      if (typeof terminal.setForegroundColor === "function" && Color.foreground) {
        terminal.setForegroundColor(Color.foreground)
      }
      if (typeof terminal.setKeyboardCursorColor === "function" && Color.accent) {
        terminal.setKeyboardCursorColor(false, Color.accent)
      }
      if (typeof terminal.fillColor !== "undefined") {
        terminal.fillColor = "transparent"
      }

      root.refreshTerminal()
    }
  }

  Connections {
    target: Color
    function onBackgroundChanged() {
      if (terminal && typeof terminal.setBackgroundColor === "function" && Color.background) {
        terminal.setBackgroundColor(Color.background)
      }
      recolorTimer.restart()
    }
    function onForegroundChanged() {
      if (terminal && typeof terminal.setForegroundColor === "function" && Color.foreground) {
        terminal.setForegroundColor(Color.foreground)
      }
      recolorTimer.restart()
    }
  }

  Timer {
    id: recolorTimer
    interval: 50
    repeat: false
    onTriggered: {
      root.reloadColorScheme(root.schemeName)
    }
  }

  onActiveTabChanged: {
    if (activeTab) {
      refreshTerminal()
      refreshTimer.restart()
    }
  }

  onVisibleChanged: {
    if (visible && activeTab) {
      refreshTerminal()
      refreshTimer.restart()
    }
  }

  Timer {
    id: refreshTimer
    interval: 60
    repeat: true
    property int count: 0
    onTriggered: {
      count++
      root.refreshTerminal()
      if (count >= 5) {
        refreshTimer.stop()
        count = 0
      }
    }
  }
}

