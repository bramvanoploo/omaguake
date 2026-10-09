import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

PopupCard {
  id: root

  property var configManager: null
  property string currentKeybinding: "CTRL + SPACE"
  property string candidateKeybinding: "CTRL + SPACE"
  property int panelHeightPercent: 50
  property string tabsPosition: "bottom"
  property bool gesturesEnabled: true
  property bool autoHideOnFocusLoss: true

  property bool keyConflict: false
  property string keyConflictMessage: ""
  property bool gestureConflict: false
  property string gestureConflictMessage: ""

  property bool isCheckingKey: false
  property bool isCheckingGesture: false

  contentWidth: Style.space(480)
  contentHeight: contentCol.implicitHeight + padding * 2

  onOpenChanged: {
    if (open) {
      loadCurrentSettings()
      checkKeyConflict(candidateKeybinding)
      if (gesturesEnabled) checkGestureConflict()
    }
  }

  function loadCurrentSettings() {
    if (configManager) {
      panelHeightPercent = configManager.heightPercent
      tabsPosition = configManager.tabsPosition
      currentKeybinding = configManager.keybinding
      candidateKeybinding = configManager.keybinding
      gesturesEnabled = configManager.gesturesEnabled
      autoHideOnFocusLoss = configManager.autoHideOnFocusLoss
    }
  }

  function checkKeyConflict(chord) {
    if (!configManager) return
    isCheckingKey = true
    keyCheckProc.command = [configManager.conflictCheckerScript, "check-key", chord]
    keyCheckProc.running = true
  }

  function checkGestureConflict() {
    if (!configManager) return
    isCheckingGesture = true
    gestureCheckProc.command = [configManager.conflictCheckerScript, "check-gesture"]
    gestureCheckProc.running = true
  }

  function applySettings() {
    if (keyConflict || (gesturesEnabled && gestureConflict)) {
      return
    }
    applyProc.command = [
      configManager.conflictCheckerScript,
      "apply",
      candidateKeybinding,
      gesturesEnabled ? "1" : "0"
    ]
    applyProc.running = true

    if (configManager) {
      configManager.saveSettings({
        heightPercent: panelHeightPercent,
        tabsPosition: tabsPosition,
        keybinding: candidateKeybinding,
        gesturesEnabled: gesturesEnabled,
        autoHideOnFocusLoss: autoHideOnFocusLoss
      })
    }
    root.close()
  }

  Process {
    id: keyCheckProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.isCheckingKey = false
        try {
          var res = JSON.parse(text)
          root.keyConflict = res.conflict === true
          root.keyConflictMessage = res.message || ""
        } catch (e) {
          root.keyConflict = false
          root.keyConflictMessage = ""
        }
      }
    }
  }

  Process {
    id: gestureCheckProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.isCheckingGesture = false
        try {
          var res = JSON.parse(text)
          root.gestureConflict = res.conflict === true
          root.gestureConflictMessage = res.message || ""
        } catch (e) {
          root.gestureConflict = false
          root.gestureConflictMessage = ""
        }
      }
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      onStreamFinished: {
        console.log("Omaguake settings applied:", text)
      }
    }
  }

  Column {
    id: contentCol
    width: parent.width
    spacing: Style.spacing.md

    // Header
    Row {
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        text: ""
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        color: Color.accent
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: "Omaguake Configuration"
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: "Drop-down terminal overlay preferences & bindings"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Color.menu.border
    }

    // Height Setting
    Column {
      width: parent.width
      spacing: Style.spacing.xs

      Row {
        width: parent.width
        Text {
          text: "Overlay Panel Height: " + root.panelHeightPercent + "%"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        PanelSlider {
          id: heightSlider
          width: parent.width - presetRow.width - Style.spacing.sm
          minimum: 20
          maximum: 100
          step: 5
          integer: true
          value: root.panelHeightPercent / 100.0
          onMoved: function(v) {
            root.panelHeightPercent = Math.round(v * 100)
          }
        }

        Row {
          id: presetRow
          spacing: 4
          Repeater {
            model: [30, 50, 75, 100]
            delegate: Button {
              text: modelData + "%"
              fontSize: Style.font.caption
              selected: root.panelHeightPercent === modelData
              onClicked: {
                root.panelHeightPercent = modelData
                heightSlider.value = modelData / 100.0
              }
            }
          }
        }
      }
    }

    // Tabs Position
    Column {
      width: parent.width
      spacing: Style.spacing.xs

      Text {
        text: "Tab Bar Position"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        color: Color.foreground
      }

      Row {
        spacing: Style.spacing.sm
        Button {
          text: "Bottom (Guake style)"
          selected: root.tabsPosition === "bottom"
          onClicked: root.tabsPosition = "bottom"
        }
        Button {
          text: "Top (Yakuake style)"
          selected: root.tabsPosition === "top"
          onClicked: root.tabsPosition = "top"
        }
      }
      Text {
        text: "Tabs align to the left with a scrollable bar and pinned '+' button"
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Color.muted
      }
    }

    // Keybinding Setting
    Column {
      width: parent.width
      spacing: Style.spacing.xs

      Text {
        text: "Toggle Keybinding"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        color: Color.foreground
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        TextField {
          id: keyField
          width: parent.width - checkBtn.width - Style.spacing.sm
          text: root.candidateKeybinding
          placeholderText: "e.g. CTRL + SPACE"
          onTextChanged: {
            root.candidateKeybinding = text.trim()
            root.checkKeyConflict(root.candidateKeybinding)
          }
        }

        Button {
          id: checkBtn
          text: root.isCheckingKey ? "Checking…" : "Verify"
          onClicked: root.checkKeyConflict(root.candidateKeybinding)
        }
      }

      // Conflict / Status box for keybinding
      Rectangle {
        width: parent.width
        height: keyMsgText.implicitHeight + 12
        radius: Style.cornerRadius
        color: root.keyConflict ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Qt.rgba(0.2, 0.8, 0.3, 0.15)
        border.color: root.keyConflict ? Color.urgent : Color.accent
        border.width: 1

        Row {
          anchors.fill: parent
          anchors.margins: 6
          spacing: 6

          Text {
            text: root.keyConflict ? "⚠" : "✓"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: root.keyConflict ? Color.urgent : Color.accent
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: keyMsgText
            width: parent.width - 24
            text: root.keyConflictMessage || (root.candidateKeybinding + " is valid")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            color: root.keyConflict ? Color.urgent : Color.foreground
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }

    // Trackpad Gestures Setting
    Column {
      width: parent.width
      spacing: Style.spacing.xs

      Row {
        width: parent.width
        Text {
          text: "Trackpad Gestures"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
          anchors.verticalCenter: parent.verticalCenter
        }

        Item { width: 1; height: 1; Layout.fillWidth: true }

        ToggleSwitch {
          id: gestureToggle
          checked: root.gesturesEnabled
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          onToggled: {
            root.gesturesEnabled = !root.gesturesEnabled
            if (root.gesturesEnabled) {
              root.checkGestureConflict()
            }
          }
        }
      }

      Text {
        text: "3-finger swipe down to SHOW, 3-finger swipe up to HIDE"
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Color.muted
      }

      // Gesture conflict box
      Rectangle {
        visible: root.gesturesEnabled
        width: parent.width
        height: gestMsgText.implicitHeight + 12
        radius: Style.cornerRadius
        color: root.gestureConflict ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Qt.rgba(0.2, 0.8, 0.3, 0.15)
        border.color: root.gestureConflict ? Color.urgent : Color.accent
        border.width: 1

        Row {
          anchors.fill: parent
          anchors.margins: 6
          spacing: 6

          Text {
            text: root.gestureConflict ? "⚠" : "✓"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: root.gestureConflict ? Color.urgent : Color.accent
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: gestMsgText
            width: parent.width - 24
            text: root.gestureConflictMessage || "Gestures available"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            color: root.gestureConflict ? Color.urgent : Color.foreground
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }

    // Auto-hide on focus loss
    Row {
      width: parent.width
      Column {
        width: parent.width - autoHideToggle.width - Style.spacing.sm
        Text {
          text: "Auto-hide on Focus Loss"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: "Automatically slide up & hide when another window receives focus"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }

      ToggleSwitch {
        id: autoHideToggle
        checked: root.autoHideOnFocusLoss
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        onToggled: root.autoHideOnFocusLoss = !root.autoHideOnFocusLoss
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Color.menu.border
    }

    // Action buttons
    Row {
      anchors.right: parent.right
      spacing: Style.spacing.sm

      Button {
        text: "Cancel"
        onClicked: root.close()
      }

      Button {
        text: "Apply & Save"
        selected: true
        // Disabled if conflict exists! Blocks the user from applying conflicting bindings/gestures!
        enabled: !root.keyConflict && !(root.gesturesEnabled && root.gestureConflict)
        opacity: enabled ? 1.0 : 0.4
        onClicked: root.applySettings()
      }
    }
  }
}
