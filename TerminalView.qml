import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "QMLTermWidget"

Item {
  id: root

  property string tabId: ""
  property string bridgeScript: ""
  property string currentTitle: "bash"
  property bool activeTab: false

  signal titleUpdated(string newTitle)
  signal processExited(int exitCode)

  QMLTermWidget {
    id: terminal
    anchors.fill: parent
    anchors.margins: 4
    focus: root.activeTab

    colorScheme: "Omaguake"
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
    }

    Component.onCompleted: {
      termSession.startShellProgram()
      if (root.activeTab) {
        terminal.forceActiveFocus()
      }
    }
  }

  function reloadColorScheme() {
    var cs = terminal.colorScheme
    terminal.colorScheme = ""
    terminal.colorScheme = cs || "Omaguake"
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

