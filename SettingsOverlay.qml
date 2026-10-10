import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

PopupCard {
  id: root

  property var configManager: null

  // Configuration properties
  property string currentKeybinding: ""
  property string candidateKeybinding: ""
  property int panelHeightPercent: 50
  property int overlayOpacityPercent: 90
  property string tabsPosition: "bottom"
  property bool gesturesEnabled: false
  property int gestureFingers: 3
  property bool autoHideOnFocusLoss: true

  // Status & conflict properties from status process
  property bool suggestedKeyConflict: false
  property string suggestedKeyConflictMessage: ""
  property bool suggestedGestureConflict: false
  property string suggestedGestureConflictMessage: ""
  property var keySuggestions: []

  // Interactive Record Key Dialog state
  property bool recordingDialogOpen: false
  property string recordedChord: ""
  property bool recordedConflict: false
  property string recordedConflictMessage: ""
  property var recordedSuggestions: []
  property bool isCheckingRecordedKey: false

  // Key Conflict Dialog state
  property bool keyConflictDialogOpen: false

  // Gestures Conflict Dialog state
  property bool gestureConflictDialogOpen: false

  // Custom Gestures Dialog state
  property bool customGesturesDialogOpen: false
  property int candidateGestureFingers: 3
  property bool customGestureConflict: false
  property string customGestureConflictMessage: ""

  padding: Style.space(20)
  contentWidth: fittedContentWidth(Style.space(490))
  contentHeight: fittedContentHeight(contentCol.implicitHeight)

  onOpenChanged: {
    if (open) {
      loadCurrentSettings()
      refreshStatus()
    } else {
      recordingDialogOpen = false
      customGesturesDialogOpen = false
      keyConflictDialogOpen = false
      gestureConflictDialogOpen = false
    }
  }

  function loadCurrentSettings() {
    if (configManager) {
      panelHeightPercent = configManager.heightPercent || 50
      overlayOpacityPercent = configManager.overlayOpacityPercent || 90
      heightSlider.value = panelHeightPercent
      opacitySlider.value = overlayOpacityPercent
      tabsPosition = configManager.tabsPosition || "bottom"
      currentKeybinding = configManager.keybinding || ""
      candidateKeybinding = configManager.keybinding || ""
      gesturesEnabled = configManager.gesturesEnabled || false
      gestureFingers = configManager.gestureFingers || 3
      autoHideOnFocusLoss = configManager.autoHideOnFocusLoss !== false
    }
  }

  function refreshStatus() {
    if (!configManager) return
    statusProc.command = [configManager.conflictCheckerScript, "status"]
    statusProc.running = true
  }

  function checkRecordedKey(chord) {
    if (!configManager || !chord) return
    isCheckingRecordedKey = true
    keyCheckProc.command = [configManager.conflictCheckerScript, "check-key", chord]
    keyCheckProc.running = true
  }

  function checkCustomGesture(fingers) {
    if (!configManager) return
    gestureCheckProc.command = [configManager.conflictCheckerScript, "check-gesture", String(fingers)]
    gestureCheckProc.running = true
  }

  function applyKeybindingDirectly(chord, unbind) {
    if (!configManager) return
    candidateKeybinding = chord
    currentKeybinding = chord
    applyProc.command = [
      configManager.conflictCheckerScript,
      "apply",
      chord,
      gesturesEnabled ? "1" : "0",
      String(gestureFingers),
      unbind ? "1" : "0"
    ]
    applyProc.running = true
    saveToConfig()
  }

  function applyGesturesDirectly(enabled, fingers, unbind) {
    if (!configManager) return
    gesturesEnabled = enabled
    gestureFingers = fingers
    applyProc.command = [
      configManager.conflictCheckerScript,
      "apply",
      currentKeybinding,
      enabled ? "1" : "0",
      String(fingers),
      unbind ? "1" : "0"
    ]
    applyProc.running = true
    saveToConfig()
  }

  function saveToConfig() {
    if (configManager) {
      configManager.saveSettings({
        heightPercent: panelHeightPercent,
        overlayOpacityPercent: overlayOpacityPercent,
        tabsPosition: tabsPosition,
        keybinding: currentKeybinding,
        gesturesEnabled: gesturesEnabled,
        gestureFingers: gestureFingers,
        autoHideOnFocusLoss: autoHideOnFocusLoss
      })
    }
  }

  function applyAllAndClose() {
    if (configManager) {
      applyProc.command = [
        configManager.conflictCheckerScript,
        "apply",
        currentKeybinding,
        gesturesEnabled ? "1" : "0",
        String(gestureFingers),
        "0"
      ]
      applyProc.running = true
      saveToConfig()
    }
    root.close()
  }

  // Background Processes
  Item {
    visible: false
    width: 0
    height: 0

    Process {
      id: statusProc
      stdout: StdioCollector {
        onStreamFinished: {
          try {
            var s = JSON.parse(text)
            root.suggestedKeyConflict = s.suggested_key_conflict === true
            root.suggestedKeyConflictMessage = s.suggested_key_conflict_message || ""
            root.suggestedGestureConflict = s.suggested_gesture_conflict === true
            root.suggestedGestureConflictMessage = s.suggested_gesture_conflict_message || ""
            root.keySuggestions = s.key_suggestions || []
            if (s.applied_key !== undefined) root.currentKeybinding = s.applied_key
            if (s.applied_gestures !== undefined) root.gesturesEnabled = s.applied_gestures
            if (s.applied_gesture_fingers !== undefined) root.gestureFingers = s.applied_gesture_fingers
          } catch(e) {}
        }
      }
    }

    Process {
      id: keyCheckProc
      stdout: StdioCollector {
        onStreamFinished: {
          root.isCheckingRecordedKey = false
          try {
            var res = JSON.parse(text)
            root.recordedConflict = res.conflict === true
            root.recordedConflictMessage = res.message || ""
            root.recordedSuggestions = res.suggestions || []
          } catch (e) {
            root.recordedConflict = false
            root.recordedConflictMessage = ""
            root.recordedSuggestions = []
          }
        }
      }
    }

    Process {
      id: gestureCheckProc
      stdout: StdioCollector {
        onStreamFinished: {
          try {
            var res = JSON.parse(text)
            root.customGestureConflict = res.conflict === true
            root.customGestureConflictMessage = res.message || ""
          } catch (e) {
            root.customGestureConflict = false
            root.customGestureConflictMessage = ""
          }
        }
      }
    }

    Process {
      id: applyProc
      stdout: StdioCollector {
        onStreamFinished: {
          root.refreshStatus()
        }
      }
    }
  }

  Flickable {
    id: scrollArea
    anchors.fill: parent
    contentHeight: contentCol.implicitHeight
    contentWidth: width
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: contentCol
      width: scrollArea.width
      spacing: Style.space(10)

    // Header
    Row {
      width: parent.width
      spacing: Style.spacing.md

      Text {
        text: "\uf489"
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        color: Color.accent
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          text: "Omaguake Configuration"
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: "Custom drop-down terminal overlay preferences & bindings"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Color.foreground, 0.1)
    }

    // 1. Overlay Height Setting
    Column {
      width: parent.width
      spacing: Style.space(5)

      Row {
        width: parent.width
        Text {
          text: "Overlay Panel Height: " + root.panelHeightPercent + "%"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Item {
          id: heightSliderContainer
          width: parent.width - heightPresetRow.width - Style.spacing.sm
          height: heightSlider.implicitHeight

          PanelSlider {
            id: heightSlider
            anchors.fill: parent
            minimum: 20
            maximum: 100
            step: 5
            integer: true
            value: root.panelHeightPercent
            onMoved: function(v) {
              root.panelHeightPercent = Math.round(v)
            }
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function(wheel) {
              scrollArea.contentY = Math.max(0, Math.min(scrollArea.contentHeight - scrollArea.height, scrollArea.contentY - wheel.angleDelta.y))
            }
          }
        }

        Row {
          id: heightPresetRow
          spacing: 4
          Repeater {
            model: [30, 50, 75, 100]
            delegate: Button {
              text: modelData + "%"
              fontSize: Style.font.caption
              selected: root.panelHeightPercent === modelData
              onClicked: {
                root.panelHeightPercent = modelData
                heightSlider.value = modelData
              }
            }
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Color.foreground, 0.08)
    }

    // 2. Terminal Opacity Setting
    Column {
      width: parent.width
      spacing: Style.space(5)

      Column {
        spacing: Style.space(1)
        Text {
          text: "Terminal Opacity: " + root.overlayOpacityPercent + "%"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: "Adjust terminal background translucency (desktop blur shows through; tab bar remains solid)"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Item {
          id: opacitySliderContainer
          width: parent.width - opacityPresetRow.width - Style.spacing.sm
          height: opacitySlider.implicitHeight

          PanelSlider {
            id: opacitySlider
            anchors.fill: parent
            minimum: 20
            maximum: 100
            step: 5
            integer: true
            value: root.overlayOpacityPercent
            onMoved: function(v) {
              root.overlayOpacityPercent = Math.round(v)
            }
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function(wheel) {
              scrollArea.contentY = Math.max(0, Math.min(scrollArea.contentHeight - scrollArea.height, scrollArea.contentY - wheel.angleDelta.y))
            }
          }
        }

        Row {
          id: opacityPresetRow
          spacing: 4
          Repeater {
            model: [50, 75, 90, 100]
            delegate: Button {
              text: modelData + "%"
              fontSize: Style.font.caption
              selected: root.overlayOpacityPercent === modelData
              onClicked: {
                root.overlayOpacityPercent = modelData
                opacitySlider.value = modelData
              }
            }
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Color.foreground, 0.08)
    }

    // 3. Tab Bar Position
    Column {
      width: parent.width
      spacing: Style.space(5)

      Column {
        spacing: Style.space(1)
        Text {
          text: "Tab Bar Position"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: "Tabs align to the left with a scrollable strip and pinned '+' button"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
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
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Color.foreground, 0.08)
    }

    // 4. Global Keybinding (Not applied by default, offers suggested & custom recording)
    Column {
      width: parent.width
      spacing: Style.space(5)

      Column {
        spacing: Style.space(1)
        Text {
          text: "Global Shortcut Keybinding"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: "Summon or hide Omaguake from anywhere. Not enabled by default."
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }

      // Action buttons row
      Row {
        spacing: Style.spacing.sm

        // Suggested Keybinding button
        Button {
          id: applySuggestedKeyBtn
          readonly property bool isSuggestedAssigned: root.currentKeybinding === "CTRL + SPACE"
          text: isSuggestedAssigned ? "✓ CTRL + SPACE" : "Apply Suggested (CTRL + SPACE)"
          enabled: !isSuggestedAssigned
          selected: isSuggestedAssigned
          opacity: enabled ? 1.0 : (isSuggestedAssigned ? 0.9 : 0.45)
          tooltipText: isSuggestedAssigned
            ? "CTRL + SPACE is currently assigned"
            : (root.suggestedKeyConflict
               ? (root.suggestedKeyConflictMessage + " Click to resolve options.")
               : "Apply suggested shortcut (CTRL + SPACE)")
          onClicked: {
            if (root.suggestedKeyConflict) {
              root.keyConflictDialogOpen = true
            } else {
              root.applyKeybindingDirectly("CTRL + SPACE", false)
            }
          }
        }

        // Record Custom Keybinding button
        Button {
          readonly property bool isCustomAssigned: !!root.currentKeybinding && root.currentKeybinding !== "CTRL + SPACE"
          text: isCustomAssigned ? ("✓ " + root.currentKeybinding) : "Record Custom Shortcut…"
          selected: isCustomAssigned
          tooltipText: isCustomAssigned
            ? (root.currentKeybinding + " is currently assigned. Click to record a different shortcut.")
            : "Record any keyboard shortcut with automatic conflict resolution"
          onClicked: {
            root.recordedChord = ""
            root.recordedConflict = false
            root.recordedConflictMessage = ""
            root.recordedSuggestions = []
            root.recordingDialogOpen = true
            Qt.callLater(function() {
              recordKeyCatcher.forceActiveFocus()
            })
          }
        }

        // Remove shortcut button
        Button {
          visible: !!root.currentKeybinding
          iconText: "\uf1f8"
          iconSize: Style.font.body
          tooltipText: "Remove global shortcut"
          onClicked: root.applyKeybindingDirectly("", false)
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Color.foreground, 0.08)
    }

    // 5. Trackpad Gestures (Not applied by default, offers suggested & custom)
    Column {
      width: parent.width
      spacing: Style.space(5)

      Column {
        spacing: Style.space(1)
        Text {
          text: "Trackpad Gestures"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: "Touchpad swipe gestures to show and hide. Not enabled by default."
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }

      // Action buttons row
      Row {
        spacing: Style.spacing.sm

        // Suggested Gestures button
        Button {
          id: applySuggestedGestBtn
          readonly property bool isSuggestedGestAssigned: root.gesturesEnabled && root.gestureFingers === 3
          text: isSuggestedGestAssigned ? "✓ 3-Finger Swipe" : "Apply Suggested (3-Finger Swipe)"
          enabled: !isSuggestedGestAssigned
          selected: isSuggestedGestAssigned
          opacity: enabled ? 1.0 : (isSuggestedGestAssigned ? 0.9 : 0.45)
          tooltipText: isSuggestedGestAssigned
            ? "3-finger gestures are enabled"
            : (root.suggestedGestureConflict
               ? (root.suggestedGestureConflictMessage + " Click to resolve options.")
               : "Enable 3-finger swipe down to show, swipe up to hide")
          onClicked: {
            if (root.suggestedGestureConflict) {
              root.gestureConflictDialogOpen = true
            } else {
              root.applyGesturesDirectly(true, 3)
            }
          }
        }

        // Custom Gestures button
        Button {
          readonly property bool isCustomGestAssigned: root.gesturesEnabled && root.gestureFingers !== 3
          text: isCustomGestAssigned ? ("✓ " + root.gestureFingers + "-Finger Swipe") : "Custom Gestures…"
          selected: isCustomGestAssigned
          tooltipText: isCustomGestAssigned
            ? (root.gestureFingers + "-finger gestures are enabled. Click to customize.")
            : "Select 3-finger or 4-finger gestures with conflict checking"
          onClicked: {
            root.candidateGestureFingers = root.gestureFingers || 3
            root.checkCustomGesture(root.candidateGestureFingers)
            root.customGesturesDialogOpen = true
          }
        }

        // Remove gestures button
        Button {
          visible: root.gesturesEnabled
          iconText: "\uf1f8"
          iconSize: Style.font.body
          tooltipText: "Remove touchpad gestures"
          onClicked: root.applyGesturesDirectly(false, 3)
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Color.foreground, 0.08)
    }

    // 6. Focus Behavior
    Item {
      width: parent.width
      height: Math.max(autoHideCol.implicitHeight, autoHideToggle.implicitHeight)

      Column {
        id: autoHideCol
        anchors.left: parent.left
        anchors.right: autoHideToggle.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          text: "Auto-hide on Focus Loss"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: "Automatically slide up and hide when clicking outside the overlay"
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
      color: Util.alpha(Color.foreground, 0.1)
    }

    // Footer Buttons
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
        onClicked: root.applyAllAndClose()
      }
    }
  }
}

  // =========================================================================
  // MODAL 1: Record Custom Keybinding Dialog with Automatic Conflict Resolving
  // =========================================================================
  Rectangle {
    id: recordModalScrim
    visible: root.recordingDialogOpen
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.7)
    radius: Style.cornerRadius
    z: 100

    MouseArea {
      anchors.fill: parent
      onClicked: {} // swallow clicks
    }

    // Modal Card
    Rectangle {
      id: recordCard
      width: parent.width - Style.space(32)
      height: recordCol.implicitHeight + Style.space(32)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.background
      border.color: Color.accent
      border.width: 1

      // Key catcher item
      Item {
        id: recordKeyCatcher
        anchors.fill: parent
        focus: root.recordingDialogOpen

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.recordingDialogOpen = false
            event.accepted = true
            return
          }

          var mods = []
          if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
          if (event.modifiers & Qt.AltModifier) mods.push("ALT")
          if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
          if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")

          var keyStr = ""
          var k = event.key
          if (k === Qt.Key_Space) keyStr = "SPACE"
          else if (k >= Qt.Key_F1 && k <= Qt.Key_F12) keyStr = "F" + (k - Qt.Key_F1 + 1)
          else if (k === Qt.Key_QuoteLeft || k === Qt.Key_AsciiTilde) keyStr = "GRAVE"
          else if (k === Qt.Key_Return || k === Qt.Key_Enter) keyStr = "RETURN"
          else if (k === Qt.Key_Tab) keyStr = "TAB"
          else if (k === Qt.Key_Backspace) keyStr = "BACKSPACE"
          else if (k >= Qt.Key_A && k <= Qt.Key_Z) keyStr = String.fromCharCode(k)
          else if (k >= Qt.Key_0 && k <= Qt.Key_9) keyStr = String.fromCharCode(k)
          else if (event.text && event.text.length === 1 && event.text.trim().length > 0) {
            keyStr = event.text.toUpperCase()
          }

          if (keyStr) {
            var chord = (mods.length > 0 ? mods.join(" + ") + " + " : "") + keyStr
            root.recordedChord = chord
            root.checkRecordedKey(chord)
            event.accepted = true
          }
        }
      }

      Column {
        id: recordCol
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(14)

        // Modal Header
        Row {
          width: parent.width
          Text {
            text: "Record Custom Keybinding"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            color: Color.foreground
          }
        }

        // Recording Display Box
        Rectangle {
          width: parent.width
          height: 60
          radius: Style.cornerRadius > 0 ? 6 : 0
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.08)
          border.color: Color.accent
          border.width: 1

          Row {
            anchors.centerIn: parent
            spacing: 8

            Text {
              text: root.recordedChord ? "⌨" : "⏺"
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              color: Color.accent
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.recordedChord || "Press key combination on keyboard (e.g. F12, ALT + SPACE)…"
              font.family: Style.font.family
              font.pixelSize: root.recordedChord ? Style.font.heading : Style.font.body
              font.bold: !!root.recordedChord
              color: root.recordedChord ? Color.foreground : Color.muted
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // Live Conflict / Status message
        Rectangle {
          visible: !!root.recordedChord
          width: parent.width
          height: recStatusText.implicitHeight + 16
          radius: Style.cornerRadius > 0 ? 4 : 0
          color: root.recordedConflict ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Qt.rgba(0.2, 0.8, 0.3, 0.15)
          border.color: root.recordedConflict ? Color.urgent : Color.accent
          border.width: 1

          Row {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Text {
              text: root.recordedConflict ? "⚠" : "✓"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: root.recordedConflict ? Color.urgent : Color.accent
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: recStatusText
              width: parent.width - 24
              text: root.isCheckingRecordedKey ? "Verifying availability in Hyprland…" : (root.recordedConflict ? root.recordedConflictMessage : (root.recordedChord + " is available!"))
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              color: root.recordedConflict ? Color.urgent : Color.foreground
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // Automatic Conflict Resolving: Suggested Alternatives
        Column {
          visible: root.recordedConflict && root.recordedSuggestions.length > 0
          width: parent.width
          spacing: 6

          Text {
            text: "Automatic Conflict Resolution — Available alternatives:"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Color.foreground
          }

          Row {
            spacing: 6
            Repeater {
              model: root.recordedSuggestions
              delegate: Button {
                text: "Use " + modelData
                fontSize: Style.font.caption
                tooltipText: "Select " + modelData + " as a conflict-free alternative"
                onClicked: {
                  root.recordedChord = modelData
                  root.checkRecordedKey(modelData)
                }
              }
            }
          }
        }

        // Override option if conflict
        Row {
          visible: root.recordedConflict
          width: parent.width
          spacing: 8

          Text {
            text: "Or take ownership:"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            anchors.verticalCenter: parent.verticalCenter
          }

          Button {
            text: "Override & Unbind Conflict"
            fontSize: Style.font.caption
            tooltipText: "Unbind the existing shortcut and assign to Omaguake"
            onClicked: {
              root.applyKeybindingDirectly(root.recordedChord, true)
              root.recordingDialogOpen = false
            }
          }
        }

        // Modal Action Buttons
        Row {
          anchors.right: parent.right
          spacing: Style.spacing.sm

          Button {
            text: "Cancel"
            onClicked: root.recordingDialogOpen = false
          }

          Button {
            text: "Apply This Shortcut"
            selected: true
            enabled: !!root.recordedChord && !root.recordedConflict && !root.isCheckingRecordedKey
            opacity: enabled ? 1.0 : 0.4
            onClicked: {
              root.applyKeybindingDirectly(root.recordedChord, false)
              root.recordingDialogOpen = false
            }
          }
        }
      }
    }
  }

  // =========================================================================
  // MODAL 2: Custom Gestures Dialog
  // =========================================================================
  Rectangle {
    id: customGesturesModalScrim
    visible: root.customGesturesDialogOpen
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.7)
    radius: Style.cornerRadius
    z: 100

    MouseArea {
      anchors.fill: parent
      onClicked: {} // swallow clicks
    }

    // Modal Card
    Rectangle {
      width: parent.width - Style.space(32)
      height: customGestCol.implicitHeight + Style.space(32)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.background
      border.color: Color.accent
      border.width: 1

      Column {
        id: customGestCol
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(14)

        Text {
          text: "Configure Touchpad Gestures"
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
          color: Color.foreground
        }

        Text {
          text: "Choose how many fingers to use for vertical swipe show/hide gestures:"
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: Color.muted
        }

        Row {
          spacing: Style.spacing.sm

          Button {
            text: "3 Fingers (Guake Standard)"
            selected: root.candidateGestureFingers === 3
            onClicked: {
              root.candidateGestureFingers = 3
              root.checkCustomGesture(3)
            }
          }

          Button {
            text: "4 Fingers"
            selected: root.candidateGestureFingers === 4
            onClicked: {
              root.candidateGestureFingers = 4
              root.checkCustomGesture(4)
            }
          }
        }

        // Conflict / Status box
        Rectangle {
          width: parent.width
          height: gestStatusMsgText.implicitHeight + 16
          radius: Style.cornerRadius > 0 ? 4 : 0
          color: root.customGestureConflict ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Qt.rgba(0.2, 0.8, 0.3, 0.15)
          border.color: root.customGestureConflict ? Color.urgent : Color.accent
          border.width: 1

          Row {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Text {
              text: root.customGestureConflict ? "⚠" : "✓"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: root.customGestureConflict ? Color.urgent : Color.accent
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: gestStatusMsgText
              width: parent.width - 24
              text: root.customGestureConflict ? root.customGestureConflictMessage : (root.candidateGestureFingers + "-finger swipe gestures are available!")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              color: root.customGestureConflict ? Color.urgent : Color.foreground
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // Action Buttons
        Row {
          anchors.right: parent.right
          spacing: Style.spacing.sm

          Button {
            text: "Cancel"
            onClicked: root.customGesturesDialogOpen = false
          }

          Button {
            visible: root.customGestureConflict
            text: "Replace Existing Gesture"
            fontSize: Style.font.caption
            tooltipText: "Disable the existing " + root.candidateGestureFingers + "-finger gesture and assign to Omaguake"
            onClicked: {
              root.applyGesturesDirectly(true, root.candidateGestureFingers, true)
              root.customGesturesDialogOpen = false
            }
          }

          Button {
            text: "Apply Gestures"
            selected: true
            enabled: !root.customGestureConflict
            opacity: enabled ? 1.0 : 0.4
            onClicked: {
              root.applyGesturesDirectly(true, root.candidateGestureFingers, false)
              root.customGesturesDialogOpen = false
            }
          }
        }
      }
    }
  }

  // =========================================================================
  // MODAL 3: Keybinding Conflict Resolution Dialog
  // =========================================================================
  Rectangle {
    id: keyConflictModalScrim
    visible: root.keyConflictDialogOpen
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.7)
    radius: Style.cornerRadius
    z: 110

    MouseArea {
      anchors.fill: parent
      onClicked: {} // Block clicks outside the dialog
    }

    Item {
      anchors.fill: parent
      focus: root.keyConflictDialogOpen

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.keyConflictDialogOpen = false
          event.accepted = true
        }
      }
    }

    Rectangle {
      width: parent.width - Style.space(32)
      height: keyConflictCol.implicitHeight + Style.space(32)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.background
      border.color: Color.urgent
      border.width: 1

      Column {
        id: keyConflictCol
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(14)

        Row {
          spacing: Style.spacing.sm
          Text {
            text: "⚠"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            color: Color.urgent
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: "Keybinding Conflict Detected"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            color: Color.foreground
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // Conflict description box
        Rectangle {
          width: parent.width
          height: keyConflictMsgText.implicitHeight + 16
          radius: Style.cornerRadius > 0 ? 4 : 0
          color: Qt.rgba(0.9, 0.2, 0.2, 0.15)
          border.color: Color.urgent
          border.width: 1

          Text {
            id: keyConflictMsgText
            anchors.fill: parent
            anchors.margins: 8
            text: root.suggestedKeyConflictMessage || "The suggested shortcut 'CTRL + SPACE' is already assigned in your system."
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            color: Color.urgent
            verticalAlignment: Text.AlignVCenter
          }
        }

        Text {
          text: "How would you like to proceed?"
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          color: Color.foreground
        }

        // Action Options
        Column {
          width: parent.width
          spacing: Style.space(8)

          // Option 1: Replace existing keybinding
          Button {
            width: parent.width
            text: "Replace Existing Keybinding (Take Ownership)"
            selected: true
            tooltipText: "Disables the conflicting binding in Hyprland and assigns CTRL + SPACE to Omaguake"
            onClicked: {
              root.keyConflictDialogOpen = false
              root.applyKeybindingDirectly("CTRL + SPACE", true)
            }
          }

          // Option 2: Record a different keybinding
          Button {
            width: parent.width
            text: "Choose a Different Keybinding (Record Input)…"
            tooltipText: "Record an alternative shortcut such as F12 or CTRL + GRAVE"
            onClicked: {
              root.keyConflictDialogOpen = false
              root.recordedChord = ""
              root.recordedConflict = false
              root.recordedConflictMessage = ""
              root.recordedSuggestions = []
              root.recordingDialogOpen = true
              Qt.callLater(function() {
                recordKeyCatcher.forceActiveFocus()
              })
            }
          }

          // Quick conflict-free suggestions row
          Row {
            visible: root.keySuggestions && root.keySuggestions.length > 0
            spacing: 6
            Text {
              text: "Suggested alternatives:"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
              anchors.verticalCenter: parent.verticalCenter
            }
            Repeater {
              model: root.keySuggestions
              delegate: Button {
                text: modelData
                fontSize: Style.font.caption
                tooltipText: "Use " + modelData + " as shortcut"
                onClicked: {
                  root.keyConflictDialogOpen = false
                  root.applyKeybindingDirectly(modelData, false)
                }
              }
            }
          }
        }

        // Footer / Cancel
        Row {
          anchors.right: parent.right
          spacing: Style.spacing.sm

          Button {
            text: "Do Nothing (Cancel)"
            onClicked: root.keyConflictDialogOpen = false
          }
        }
      }
    }
  }

  // =========================================================================
  // MODAL 4: Gesture Conflict Resolution Dialog
  // =========================================================================
  Rectangle {
    id: gestureConflictModalScrim
    visible: root.gestureConflictDialogOpen
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.7)
    radius: Style.cornerRadius
    z: 110

    MouseArea {
      anchors.fill: parent
      onClicked: {} // Block clicks outside the dialog
    }

    Item {
      anchors.fill: parent
      focus: root.gestureConflictDialogOpen

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.gestureConflictDialogOpen = false
          event.accepted = true
        }
      }
    }

    Rectangle {
      width: parent.width - Style.space(32)
      height: gestureConflictCol.implicitHeight + Style.space(32)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.background
      border.color: Color.urgent
      border.width: 1

      Column {
        id: gestureConflictCol
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(14)

        Row {
          spacing: Style.spacing.sm
          Text {
            text: "⚠"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            color: Color.urgent
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: "Trackpad Gesture Conflict Detected"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            color: Color.foreground
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // Conflict description box
        Rectangle {
          width: parent.width
          height: gestureConflictMsgText.implicitHeight + 16
          radius: Style.cornerRadius > 0 ? 4 : 0
          color: Qt.rgba(0.9, 0.2, 0.2, 0.15)
          border.color: Color.urgent
          border.width: 1

          Text {
            id: gestureConflictMsgText
            anchors.fill: parent
            anchors.margins: 8
            text: root.suggestedGestureConflictMessage || "A 3-finger swipe gesture is already configured on your system."
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            color: Color.urgent
            verticalAlignment: Text.AlignVCenter
          }
        }

        Text {
          text: "How would you like to proceed?"
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          color: Color.foreground
        }

        // Action Options
        Column {
          width: parent.width
          spacing: Style.space(8)

          // Option 1: Replace existing gesture
          Button {
            width: parent.width
            text: "Replace Existing Gestures (3-Finger Swipe Down/Up)"
            selected: true
            tooltipText: "Disables the conflicting 3-finger gestures and assigns swipe down/up to Omaguake"
            onClicked: {
              root.gestureConflictDialogOpen = false
              root.applyGesturesDirectly(true, 3, true)
            }
          }

          // Option 2: Choose 4-finger gestures
          Button {
            width: parent.width
            text: "Use 4-Finger Swipe Gestures Instead…"
            tooltipText: "Open Custom Gestures dialog to select 4 fingers"
            onClicked: {
              root.gestureConflictDialogOpen = false
              root.candidateGestureFingers = 4
              root.checkCustomGesture(4)
              root.customGesturesDialogOpen = true
            }
          }
        }

        // Footer / Cancel
        Row {
          anchors.right: parent.right
          spacing: Style.spacing.sm

          Button {
            text: "Do Nothing (Cancel)"
            onClicked: root.gestureConflictDialogOpen = false
          }
        }
      }
    }
  }
}
