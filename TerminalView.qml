import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import QMLTermWidget 2.0

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

