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

  // Custom Gestures Dialog state
  property bool customGesturesDialogOpen: false
  property int candidateGestureFingers: 3
  property bool customGestureConflict: false
  property string customGestureConflictMessage: ""

  padding: Style.space(20)
  contentWidth: fittedContentWidth(Style.space(560))
  contentHeight: fittedContentHeight(contentCol.implicitHeight)

  onOpenChanged: {
    if (open) {
      loadCurrentSettings()
      refreshStatus()
    } else {
      recordingDialogOpen = false
      customGesturesDialogOpen = false
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

  function applyGesturesDirectly(enabled, fingers) {
    if (!configManager) return
    gesturesEnabled = enabled
    gestureFingers = fingers
    applyProc.command = [
      configManager.conflictCheckerScript,
      "apply",
      currentKeybinding,
      enabled ? "1" : "0",
      String(fingers),
      "0"
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
      spacing: Style.space(18)

    // Header
    Row {
      width: parent.width
      spacing: Style.spacing.md

      Text {
        text: ""
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
      spacing: Style.space(8)

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

    // 2. Overlay Opacity Setting
    Column {
      width: parent.width
      spacing: Style.space(8)

      Column {
        spacing: Style.space(2)
        Text {
          text: "Overlay Opacity: " + root.overlayOpacityPercent + "%"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: "Adjust terminal background translucency (desktop blur shows through)"
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
      spacing: Style.space(8)

      Column {
        spacing: Style.space(2)
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
      spacing: Style.space(8)

      Column {
        spacing: Style.space(2)
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

      // Status indicator
      Row {
        spacing: Style.spacing.sm
        Rectangle {
          height: 26
          width: keyStatusRow.implicitWidth + 16
          radius: Style.cornerRadius > 0 ? 4 : 0
          color: root.currentKeybinding ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
          border.color: root.currentKeybinding ? Color.accent : Color.menu.border
          border.width: 1

          Row {
            id: keyStatusRow
            anchors.centerIn: parent
            spacing: 6
            Text {
              text: root.currentKeybinding ? ("⌨ " + root.currentKeybinding) : "No shortcut configured"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: !!root.currentKeybinding
              color: root.currentKeybinding ? Color.accent : Color.muted
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // Remove shortcut button if active
        Button {
          visible: !!root.currentKeybinding
          text: "Remove"
          fontSize: Style.font.caption
          tooltipText: "Disable global shortcut"
          onClicked: root.applyKeybindingDirectly("", false)
        }
      }

      // Action buttons row
      Row {
        spacing: Style.spacing.sm

        // Suggested Keybinding button
        Button {
          id: applySuggestedKeyBtn
          readonly property bool isSuggestedAssigned: root.currentKeybinding === "CTRL + SPACE"
          readonly property bool isSuggestedDisabled: root.suggestedKeyConflict && !isSuggestedAssigned
          text: isSuggestedAssigned ? "✓ CTRL + SPACE Active" : "Apply Suggested (CTRL + SPACE)"
          enabled: !isSuggestedDisabled && !isSuggestedAssigned
          selected: isSuggestedAssigned
          opacity: enabled ? 1.0 : (isSuggestedAssigned ? 0.9 : 0.45)
          tooltipText: isSuggestedDisabled
            ? (root.suggestedKeyConflictMessage || "CTRL + SPACE is already in use by another shortcut. Choose a custom shortcut.")
            : (isSuggestedAssigned ? "CTRL + SPACE is currently assigned" : "Apply suggested shortcut (CTRL + SPACE)")
          onClicked: {
            root.applyKeybindingDirectly("CTRL + SPACE", false)
          }
        }

        // Record Custom Keybinding button
        Button {
          text: "Record Custom Shortcut…"
          tooltipText: "Record any keyboard shortcut with automatic conflict resolution"
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
      spacing: Style.space(8)

      Column {
        spacing: Style.space(2)
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

      // Status indicator
      Row {
        spacing: Style.spacing.sm
        Rectangle {
          height: 26
          width: gestStatusRow.implicitWidth + 16
          radius: Style.cornerRadius > 0 ? 4 : 0
          color: root.gesturesEnabled ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
          border.color: root.gesturesEnabled ? Color.accent : Color.menu.border
          border.width: 1

          Row {
            id: gestStatusRow
            anchors.centerIn: parent
            spacing: 6
            Text {
              text: root.gesturesEnabled ? ("🖐 " + root.gestureFingers + "-finger swipe (down = show, up = hide)") : "No gestures configured"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: root.gesturesEnabled
              color: root.gesturesEnabled ? Color.accent : Color.muted
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // Remove gestures button if active
        Button {
          visible: root.gesturesEnabled
          text: "Remove"
          fontSize: Style.font.caption
          tooltipText: "Disable touchpad gestures"
          onClicked: root.applyGesturesDirectly(false, 3)
        }
      }

      // Action buttons row
      Row {
        spacing: Style.spacing.sm

        // Suggested Gestures button
        Button {
          id: applySuggestedGestBtn
          readonly property bool isSuggestedDisabled: root.suggestedGestureConflict && !root.gesturesEnabled
          text: (root.gesturesEnabled && root.gestureFingers === 3) ? "✓ 3-Finger Swipe Active" : "Apply Suggested (3-Finger Swipe)"
          enabled: !isSuggestedDisabled && !(root.gesturesEnabled && root.gestureFingers === 3)
          selected: root.gesturesEnabled && root.gestureFingers === 3
          opacity: enabled ? 1.0 : ((root.gesturesEnabled && root.gestureFingers === 3) ? 0.9 : 0.45)
          tooltipText: isSuggestedDisabled
            ? (root.suggestedGestureConflictMessage || "3-finger gestures conflict with existing system settings.")
            : ((root.gesturesEnabled && root.gestureFingers === 3) ? "3-finger gestures are active" : "Enable 3-finger swipe down to show, swipe up to hide")
          onClicked: {
            root.applyGesturesDirectly(true, 3)
          }
        }

        // Custom Gestures button
        Button {
          text: "Custom Gestures…"
          tooltipText: "Select 3-finger or 4-finger gestures with conflict checking"
          onClicked: {
            root.candidateGestureFingers = root.gestureFingers || 3
            root.checkCustomGesture(root.candidateGestureFingers)
            root.customGesturesDialogOpen = true
          }
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
        spacing: Style.space(2)

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
            text: "Apply Gestures"
            selected: true
            enabled: !root.customGestureConflict
            opacity: enabled ? 1.0 : 0.4
            onClicked: {
              root.applyGesturesDirectly(true, root.candidateGestureFingers)
              root.customGesturesDialogOpen = false
            }
          }
        }
      }
    }
  }
}
