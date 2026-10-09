import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import QMLTermWidget 2.0

Item {
  id: root

  property string tabId: ""
  property string bridgeScript: ""
  property string currentTitle: "bash"
  property bool activeTab: false

  property string lastCommand: ""
  property string typedLine: ""

  signal titleUpdated(string newTitle)
  signal commandUpdated(string commandText)
  signal processExited(int exitCode)

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
      initialWorkingDirectory: Quickshell.env("HOME") || "/home/bram"

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
      if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
        if (event.key === Qt.Key_C) {
          terminal.copyClipboard()
          event.accepted = true
          return
        } else if (event.key === Qt.Key_V) {
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
      terminal.colorScheme = root.schemeName
    }
  }

  Connections {
    target: Color
    function onBackgroundChanged() {
      recolorTimer.restart()
    }
    function onForegroundChanged() {
      recolorTimer.restart()
    }
  }

  Timer {
    id: recolorTimer
    interval: 80
    repeat: false
    onTriggered: {
      root.reloadColorScheme()
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

