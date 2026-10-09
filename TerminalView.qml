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

  property string activeLine: ""
  property string typedLine: ""

  signal titleUpdated(string newTitle)
  signal lineUpdated(string activeLineText)
  signal processExited(int exitCode)

  property string schemeName: "Omaguake"

  onSchemeNameChanged: {
    if (terminal && schemeName.length > 0) {
      terminal.colorScheme = schemeName
    }
  }

  function updateTyped(newTyped) {
    typedLine = newTyped
    activeLine = newTyped
    lineUpdated(newTyped)
  }

  Timer {
    id: procCheckTimer
    interval: 500
    repeat: true
    running: root.activeTab
    onTriggered: {
      try {
        var fg = ""
        if (termSession && typeof termSession.foregroundProcessName === "function") {
          fg = termSession.foregroundProcessName()
        } else if (termSession && termSession.foregroundProcessName !== undefined) {
          fg = String(termSession.foregroundProcessName || "")
        }
        if (fg && fg !== "bash" && fg !== "sh" && fg !== "zsh" && fg !== "fish") {
          if (root.activeLine !== fg) {
            root.activeLine = fg
            root.lineUpdated(fg)
          }
        } else if (fg === "bash" || fg === "sh" || fg === "zsh" || fg === "fish") {
          if (root.activeLine !== root.typedLine) {
            root.activeLine = root.typedLine
            root.lineUpdated(root.typedLine)
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
          event.accepted = true
          return
        }
      }

      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.updateTyped("")
      } else if (event.key === Qt.Key_Backspace) {
        if (root.typedLine.length > 0) {
          root.updateTyped(root.typedLine.slice(0, -1))
        }
      } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_C || event.key === Qt.Key_U)) {
        root.updateTyped("")
      } else if (event.text && event.text.length > 0 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        var ch = event.text
        if (ch >= " " && ch !== "\r" && ch !== "\n") {
          root.updateTyped(root.typedLine + ch)
        }
      }
    }

    Component.onCompleted: {
      termSession.startShellProgram()
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
      Qt.callLater(function() {
        terminal.forceActiveFocus()
      })
    }
  }
}

