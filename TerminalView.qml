import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "QMLTermWidget"

Item {
  id: root

  property string tabId: ""
  property string currentTitle: "bash"
  property bool activeTab: false

  property string lastCommand: ""
  property string typedLine: ""

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

  onSchemeNameChanged: {
    if (terminal && schemeName.length > 0) {
      terminal.colorScheme = schemeName
    }
  }

  function getForegroundProcess() {
    try {
      if (termSession && typeof termSession.foregroundProcessName === "function") {
        return termSession.foregroundProcessName() || ""
      } else if (termSession && termSession.foregroundProcessName !== undefined) {
        return String(termSession.foregroundProcessName || "")
      }
    } catch(e) {}
    return ""
  }

  Timer {
    id: procCheckTimer
    interval: 250
    repeat: true
    running: root.activeTab
    onTriggered: {
      try {
        var fg = root.getForegroundProcess()
        if (fg && fg !== "bash" && fg !== "sh" && fg !== "zsh" && fg !== "fish") {
          if (!root.lastCommand || root.lastCommand.indexOf(fg) !== 0) {
            root.lastCommand = fg
            root.commandUpdated(fg)
          }
        }
      } catch(e) {}
    }
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

  QMLTermWidget {
    id: terminal
    anchors.fill: parent
    anchors.leftMargin: 16
    anchors.rightMargin: 16
    anchors.topMargin: 12
    anchors.bottomMargin: 10
    focus: root.activeTab
    Keys.priority: Keys.BeforeItem

    colorScheme: root.schemeName
    font.family: (Style.resolvedFontFamily && Style.resolvedFontFamily !== "monospace")
      ? Style.resolvedFontFamily
      : "JetBrainsMono Nerd Font"
    font.pointSize: 10

    session: QMLTermSession {
      id: termSession
      initialWorkingDirectory: Quickshell.env("HOME") || "."

      onTitleChanged: function() {
        if (termSession.title && termSession.title !== root.currentTitle) {
          root.currentTitle = termSession.title
          root.titleUpdated(termSession.title)
        }
      }

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
        event.accepted = true
        return
      } else if (isPaste) {
        terminal.pasteClipboard()
        try {
          var pasted = Quickshell.clipboardText || ""
          if (pasted.length > 0) {
            root.typedLine += pasted
          }
        } catch(e) {}
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
        var fg = root.getForegroundProcess()
        var isShell = (!fg || fg === "bash" || fg === "sh" || fg === "zsh" || fg === "fish")
        if (isShell) {
          var entered = root.typedLine.trim()
          root.typedLine = ""
          if (entered.length > 0) {
            root.lastCommand = entered
            root.commandUpdated(entered)
          }
        } else {
          root.typedLine = ""
        }
      } else if (event.key === Qt.Key_Backspace) {
        if (root.typedLine.length > 0) {
          root.typedLine = root.typedLine.slice(0, -1)
        }
      } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_C || event.key === Qt.Key_U)) {
        root.typedLine = ""
      } else if (event.text && event.text.length > 0 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        var ch = event.text
        if (ch >= " " && ch !== "\r" && ch !== "\n") {
          root.typedLine += ch
        }
      }
    }

    Component.onCompleted: {
      termSession.startShellProgram()
      root.reloadColorScheme(root.schemeName)
      if (root.activeTab) {
        root.refreshTerminal()
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    z: -1
    onPressed: {
      root.refreshTerminal()
    }
  }

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
      if (root.schemeName && root.schemeName.length > 0) {
        terminal.colorScheme = ""
        terminal.colorScheme = root.schemeName
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

