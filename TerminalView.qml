import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TerminalBuffer.js" as TerminalBuffer

Item {
  id: root

  property string tabId: ""
  property string bridgeScript: ""
  property int cols: 120
  property int rows: 35
  property string currentTitle: "bash"
  property bool activeTab: false

  // Palette from Omarchy themes
  property color termBackground: Color.menu.background
  property color termForeground: Color.foreground
  property string termFontFamily: "monospace"
  property int termFontSize: 13
  property real termLineHeight: termFontSize * 1.35

  signal titleUpdated(string newTitle)
  signal processExited(int exitCode)

  property var termBuffer: null
  property bool autoScroll: true
  property int totalLines: 0

  Component.onCompleted: {
    termBuffer = TerminalBuffer.createTerminal({
      cols: root.cols,
      rows: root.rows,
      maxLines: 2000
    })
    if (bridgeScript) {
      ptyProc.running = true
    }
  }

  Component.onDestruction: {
    if (ptyProc.running) {
      ptyProc.write(JSON.stringify({ t: "kill" }) + "\n")
    }
  }

  onActiveTabChanged: {
    if (activeTab) {
      Qt.callLater(function() {
        keyReceiver.forceActiveFocus()
      })
    }
  }

  function sendInput(str) {
    if (ptyProc.running) {
      ptyProc.write(JSON.stringify({ t: "in", d: str }) + "\n")
    }
  }

  function resizeTerminal(newCols, newRows) {
    root.cols = Math.max(20, newCols)
    root.rows = Math.max(5, newRows)
    if (ptyProc.running) {
      ptyProc.write(JSON.stringify({ t: "resize", cols: root.cols, rows: root.rows }) + "\n")
    }
  }

  function handleStdout(jsonLine) {
    if (!jsonLine || !jsonLine.trim()) return
    try {
      var msg = JSON.parse(jsonLine)
      if (msg.t === "out") {
        termBuffer.write(msg.d)
        refreshLines()
        var newTitle = termBuffer.getTitle()
        if (newTitle && newTitle !== currentTitle) {
          currentTitle = newTitle
          titleUpdated(newTitle)
        }
      } else if (msg.t === "exit") {
        processExited(msg.code || 0)
      }
    } catch (e) {
      // Non-json or raw line
      termBuffer.write(jsonLine + "\n")
      refreshLines()
    }
  }

  function refreshLines() {
    var rawLines = termBuffer.getLines()
    var count = rawLines.length
    lineModel.clear()
    for (var i = 0; i < count; i++) {
      lineModel.append({ text: rawLines[i] || " " })
    }
    root.totalLines = count
    if (autoScroll) {
      Qt.callLater(function() {
        lineView.positionViewAtEnd()
      })
    }
  }

  ListModel {
    id: lineModel
  }

  Process {
    id: ptyProc
    command: [root.bridgeScript, String(root.cols), String(root.rows)]
    stdinEnabled: true
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        root.handleStdout(data)
      }
    }
    onExited: function(exitCode) {
      root.processExited(exitCode)
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.termBackground

    MouseArea {
      anchors.fill: parent
      onPressed: {
        keyReceiver.forceActiveFocus()
      }
      onWheel: function(wheel) {
        if (wheel.angleDelta.y > 0) {
          root.autoScroll = false
          lineView.flick(0, 300)
        } else if (wheel.angleDelta.y < 0) {
          lineView.flick(0, -300)
          if (lineView.atYEnd) {
            root.autoScroll = true
          }
        }
      }
    }

    ListView {
      id: lineView
      anchors.fill: parent
      anchors.margins: 10
      clip: true
      model: lineModel
      boundsBehavior: Flickable.StopAtBounds

      delegate: Text {
        width: lineView.width
        text: model.text
        textFormat: Text.RichText
        font.family: root.termFontFamily
        font.pixelSize: root.termFontSize
        color: root.termForeground
        wrapMode: Text.NoWrap
        lineHeight: root.termLineHeight
        lineHeightMode: Text.FixedHeight
      }

      onMovementEnded: {
        if (atYEnd) root.autoScroll = true
      }
    }

    // Key receiver item
    Item {
      id: keyReceiver
      anchors.fill: parent
      focus: root.activeTab

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var mods = event.modifiers
        var key = event.key
        var text = event.text

        // Clipboard copy/paste
        if ((mods & Qt.ControlModifier) && (mods & Qt.ShiftModifier)) {
          if (key === Qt.Key_C) {
            // Copy
            event.accepted = true
            return
          } else if (key === Qt.Key_V) {
            // Paste from clipboard
            if (Quickshell.clipboardText) {
              root.sendInput(Quickshell.clipboardText)
            }
            event.accepted = true
            return
          }
        }

        // Ctrl combinations
        if (mods & Qt.ControlModifier) {
          if (key >= Qt.Key_A && key <= Qt.Key_Z) {
            var code = key - Qt.Key_A + 1
            root.sendInput(String.fromCharCode(code))
            event.accepted = true
            return
          } else if (key === Qt.Key_Space) {
            root.sendInput("\x00")
            event.accepted = true
            return
          } else if (key === Qt.Key_BracketLeft) {
            root.sendInput("\x1b")
            event.accepted = true
            return
          } else if (key === Qt.Key_Backslash) {
            root.sendInput("\x1c")
            event.accepted = true
            return
          }
        }

        // Special keys
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
          root.sendInput("\r")
          event.accepted = true
          return
        } else if (key === Qt.Key_Backspace) {
          root.sendInput("\x7f")
          event.accepted = true
          return
        } else if (key === Qt.Key_Tab) {
          root.sendInput("\t")
          event.accepted = true
          return
        } else if (key === Qt.Key_Escape) {
          root.sendInput("\x1b")
          event.accepted = true
          return
        } else if (key === Qt.Key_Up) {
          root.sendInput("\x1b[A")
          event.accepted = true
          return
        } else if (key === Qt.Key_Down) {
          root.sendInput("\x1b[B")
          event.accepted = true
          return
        } else if (key === Qt.Key_Right) {
          root.sendInput("\x1b[C")
          event.accepted = true
          return
        } else if (key === Qt.Key_Left) {
          root.sendInput("\x1b[D")
          event.accepted = true
          return
        } else if (key === Qt.Key_Home) {
          root.sendInput("\x1b[H")
          event.accepted = true
          return
        } else if (key === Qt.Key_End) {
          root.sendInput("\x1b[F")
          event.accepted = true
          return
        } else if (key === Qt.Key_PageUp) {
          root.sendInput("\x1b[5~")
          event.accepted = true
          return
        } else if (key === Qt.Key_PageDown) {
          root.sendInput("\x1b[6~")
          event.accepted = true
          return
        } else if (key === Qt.Key_Delete) {
          root.sendInput("\x1b[3~")
          event.accepted = true
          return
        } else if (key === Qt.Key_Insert) {
          root.sendInput("\x1b[2~")
          event.accepted = true
          return
        }

        // Regular printable characters
        if (text && text.length > 0) {
          root.sendInput(text)
          event.accepted = true
          return
        }
      }
    }
  }
}
