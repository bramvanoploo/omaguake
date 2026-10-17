import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "i18n.js" as I18n

PopupCard {
  id: root

  property var configManager: null

  // Configuration properties
  property string currentKeybinding: ""
  property string candidateKeybinding: ""
  property int panelHeightPercent: 50
  property int panelWidthPercent: 100
  property int overlayOpacityPercent: 90
  property string tabsPosition: "bottom"
  property string selectedLanguage: ""

  function tr(key, params) {
    var _ = selectedLanguage
    return I18n.t(key, params)
  }

  onSelectedLanguageChanged: {
    I18n.setLanguageOverride(selectedLanguage)
  }

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

  // Language Dialog state
  property bool languageDialogOpen: false

  readonly property var languageList: [
    { code: "", label: "System Default (Auto)" },
    { code: "en", label: "English" },
    { code: "nl", label: "Nederlands / Vlaams (Dutch)" },
    { code: "es", label: "Español (Spanish)" },
    { code: "fr", label: "Français (French)" },
    { code: "de", label: "Deutsch (German)" },
    { code: "it", label: "Italiano (Italian)" },
    { code: "pt", label: "Português (Portuguese)" },
    { code: "no", label: "Norsk (Norwegian)" },
    { code: "sv", label: "Svenska (Swedish)" },
    { code: "fi", label: "Suomi (Finnish)" },
    { code: "ru", label: "Русский (Russian)" },
    { code: "hr", label: "Hrvatski (Croatian)" },
    { code: "zh", label: "中文 (Chinese)" },
    { code: "ja", label: "日本語 (Japanese)" },
    { code: "ar", label: "العربية (Arabic)" }
  ]

  function languageDisplayName(code) {
    if (!code) return tr("lang_system")
    for (var i = 0; i < languageList.length; i++) {
      if (languageList[i].code === code) return languageList[i].label
    }
    return code
  }

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
      languageDialogOpen = false
    }
  }

  function loadCurrentSettings() {
    if (configManager) {
      panelHeightPercent = configManager.heightPercent || 50
      panelWidthPercent = configManager.widthPercent || 100
      overlayOpacityPercent = configManager.overlayOpacityPercent || 90
      heightSlider.value = panelHeightPercent
      widthSlider.value = panelWidthPercent
      opacitySlider.value = overlayOpacityPercent
      tabsPosition = configManager.tabsPosition || "bottom"
      selectedLanguage = configManager.language || ""
      I18n.setLanguageOverride(selectedLanguage)
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
        widthPercent: panelWidthPercent,
        overlayOpacityPercent: overlayOpacityPercent,
        tabsPosition: tabsPosition,
        language: selectedLanguage,
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
      spacing: Style.space(14)

      // Header icon: sized to span the title + subtitle block
      Text {
        text: "\uf489"
        font.family: Style.font.family
        font.pixelSize: Math.max(Style.font.heading, Math.round(headerTextCol.implicitHeight))
        color: Color.accent
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: headerTextCol
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Row {
          spacing: Style.space(8)

          Text {
            text: root.tr("config_title")
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            color: Color.foreground
            anchors.verticalCenter: parent.verticalCenter
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(18)
            width: versionText.implicitWidth + Style.space(12)
            radius: Style.cornerRadius > 0 ? 4 : 0
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4)
            border.width: 1

            Text {
              id: versionText
              anchors.centerIn: parent
              text: "v" + (configManager && configManager.version ? configManager.version : "0.9.8")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              color: Color.accent
            }
          }
        }

        Text {
          text: root.tr("config_subtitle")
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
          text: root.tr("panel_height", { val: root.panelHeightPercent })
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
          spacing: Style.space(4)
          Repeater {
            model: [30, 50, 75, 100]
            delegate: Button {
              width: Style.space(46)
              horizontalPadding: 0
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

    // 2. Overlay Width Setting
    Column {
      width: parent.width
      spacing: Style.space(5)

      Column {
        spacing: Style.space(1)
        Text {
          text: root.tr("panel_width", { val: root.panelWidthPercent })
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: root.tr("panel_width_desc")
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Item {
          id: widthSliderContainer
          width: parent.width - widthPresetRow.width - Style.spacing.sm
          height: widthSlider.implicitHeight

          PanelSlider {
            id: widthSlider
            anchors.fill: parent
            minimum: 20
            maximum: 100
            step: 5
            integer: true
            value: root.panelWidthPercent
            onMoved: function(v) {
              root.panelWidthPercent = Math.round(v)
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
          id: widthPresetRow
          spacing: Style.space(4)
          Repeater {
            model: [50, 75, 90, 100]
            delegate: Button {
              width: Style.space(46)
              horizontalPadding: 0
              text: modelData + "%"
              fontSize: Style.font.caption
              selected: root.panelWidthPercent === modelData
              onClicked: {
                root.panelWidthPercent = modelData
                widthSlider.value = modelData
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

    // 3. Terminal Opacity Setting
    Column {
      width: parent.width
      spacing: Style.space(5)

      Column {
        spacing: Style.space(1)
        Text {
          text: root.tr("terminal_opacity", { val: root.overlayOpacityPercent })
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: root.tr("terminal_opacity_desc")
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
          spacing: Style.space(4)
          Repeater {
            model: [50, 75, 90, 100]
            delegate: Button {
              width: Style.space(46)
              horizontalPadding: 0
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

    // 4. Tab Bar Position
    Column {
      width: parent.width
      spacing: Style.space(5)

      Column {
        spacing: Style.space(1)
        Text {
          text: root.tr("tabs_position")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: root.tr("tabs_position_desc")
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm
        Button {
          width: Math.floor((parent.width - Style.spacing.sm) / 2)
          text: root.tr("tabs_bottom")
          selected: root.tabsPosition === "bottom"
          onClicked: root.tabsPosition = "bottom"
        }
        Button {
          width: Math.floor((parent.width - Style.spacing.sm) / 2)
          text: root.tr("tabs_top")
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

    // 5. Global Shortcut Keybinding (Not applied by default, offers suggested & custom recording)
    Column {
      width: parent.width
      spacing: Style.space(5)

      Column {
        spacing: Style.space(1)
        Text {
          text: root.tr("keybinding_title")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: root.tr("keybinding_desc")
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }

      // Action buttons row
      Row {
        id: keybindBtnRow
        width: parent.width
        spacing: Style.spacing.sm

        readonly property real trashW: !!root.currentKeybinding ? (Style.space(38) + Style.spacing.sm) : 0
        readonly property real actionBtnW: Math.floor((width - trashW - Style.spacing.sm) / 2)

        // Suggested Keybinding button
        Button {
          id: applySuggestedKeyBtn
          width: keybindBtnRow.actionBtnW
          readonly property bool isSuggestedAssigned: root.currentKeybinding === "CTRL + SPACE"
          text: isSuggestedAssigned ? root.tr("assigned_key", { chord: "CTRL + SPACE" }) : root.tr("apply_suggested_key")
          enabled: !isSuggestedAssigned
          selected: isSuggestedAssigned
          opacity: enabled ? 1.0 : (isSuggestedAssigned ? 0.9 : 0.45)
          tooltipText: isSuggestedAssigned
            ? root.tr("key_assigned_tooltip", { chord: "CTRL + SPACE" })
            : (root.suggestedKeyConflict
               ? (root.suggestedKeyConflictMessage + " " + root.tr("click_to_resolve"))
               : root.tr("key_suggested_tooltip"))
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
          width: keybindBtnRow.actionBtnW
          readonly property bool isCustomAssigned: !!root.currentKeybinding && root.currentKeybinding !== "CTRL + SPACE"
          text: isCustomAssigned ? root.tr("assigned_key", { chord: root.currentKeybinding }) : root.tr("record_custom_key")
          selected: isCustomAssigned
          tooltipText: isCustomAssigned
            ? root.tr("key_record_tooltip", { chord: root.currentKeybinding })
            : root.tr("key_record_default_tooltip")
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
          width: Style.space(38)
          iconText: "\uf1f8"
          iconSize: Style.font.body
          tooltipText: root.tr("remove_shortcut_tooltip")
          onClicked: root.applyKeybindingDirectly("", false)
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Color.foreground, 0.08)
    }

    // 6. Trackpad Gestures (Not applied by default, offers suggested & custom)
    Column {
      width: parent.width
      spacing: Style.space(5)

      Column {
        spacing: Style.space(1)
        Text {
          text: root.tr("gestures_title")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: root.tr("gestures_desc")
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }

      // Action buttons row
      Row {
        id: gesturesBtnRow
        width: parent.width
        spacing: Style.spacing.sm

        readonly property real trashW: root.gesturesEnabled ? (Style.space(38) + Style.spacing.sm) : 0
        readonly property real actionBtnW: Math.floor((width - trashW - Style.spacing.sm) / 2)

        // Suggested Gestures button
        Button {
          id: applySuggestedGestBtn
          width: gesturesBtnRow.actionBtnW
          readonly property bool isSuggestedGestAssigned: root.gesturesEnabled && root.gestureFingers === 3
          text: isSuggestedGestAssigned ? root.tr("assigned_gestures", { fingers: "3" }) : root.tr("apply_suggested_gestures")
          enabled: !isSuggestedGestAssigned
          selected: isSuggestedGestAssigned
          opacity: enabled ? 1.0 : (isSuggestedGestAssigned ? 0.9 : 0.45)
          tooltipText: isSuggestedGestAssigned
            ? root.tr("gestures_assigned_tooltip", { fingers: "3" })
            : (root.suggestedGestureConflict
               ? (root.suggestedGestureConflictMessage + " " + root.tr("click_to_resolve"))
               : root.tr("gestures_suggested_tooltip"))
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
          width: gesturesBtnRow.actionBtnW
          readonly property bool isCustomGestAssigned: root.gesturesEnabled && root.gestureFingers !== 3
          text: isCustomGestAssigned ? root.tr("assigned_gestures", { fingers: root.gestureFingers }) : root.tr("custom_gestures")
          selected: isCustomGestAssigned
          tooltipText: isCustomGestAssigned
            ? root.tr("gestures_customize_tooltip", { fingers: root.gestureFingers })
            : root.tr("gestures_default_tooltip")
          onClicked: {
            root.candidateGestureFingers = root.gestureFingers || 3
            root.checkCustomGesture(root.candidateGestureFingers)
            root.customGesturesDialogOpen = true
          }
        }

        // Remove gestures button
        Button {
          visible: root.gesturesEnabled
          width: Style.space(38)
          iconText: "\uf1f8"
          iconSize: Style.font.body
          tooltipText: root.tr("remove_gestures_tooltip")
          onClicked: root.applyGesturesDirectly(false, 3)
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Color.foreground, 0.08)
    }

    // 7. Focus Behavior
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
          text: root.tr("autohide_title")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: root.tr("autohide_desc")
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
      color: Util.alpha(Color.foreground, 0.08)
    }

    // 8. Interface Language Setting (All the way at the bottom)
    Column {
      width: parent.width
      spacing: Style.space(5)

      Column {
        spacing: Style.space(1)
        Text {
          text: root.tr("language_title")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }
        Text {
          text: root.tr("language_desc")
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }
      }

      Button {
        id: langSelectorBtn
        width: parent.width
        text: "🌐  " + root.languageDisplayName(root.selectedLanguage)
        fontSize: Style.font.bodySmall
        onClicked: {
          root.languageDialogOpen = true
        }
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
        id: cancelBtn
        width: Math.max(saveBtn.implicitWidth, Style.space(120))
        text: root.tr("cancel")
        onClicked: root.close()
      }

      Button {
        id: saveBtn
        width: Math.max(implicitWidth, Style.space(120))
        text: root.tr("apply")
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
            text: root.tr("modal_record_title")
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
              text: root.recordedChord || root.tr("modal_record_instructions")
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
              text: root.isCheckingRecordedKey ? root.tr("modal_record_verifying") : (root.recordedConflict ? root.recordedConflictMessage : root.tr("modal_record_available", { chord: root.recordedChord }))
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
            text: root.tr("modal_record_alternatives")
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
                text: root.tr("modal_record_use_alt", { chord: modelData })
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
            text: root.tr("modal_record_ownership")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            anchors.verticalCenter: parent.verticalCenter
          }

          Button {
            text: root.tr("modal_record_override")
            fontSize: Style.font.caption
            tooltipText: "Unbind the existing shortcut and assign to OmaGuake"
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
            id: recCancelBtn
            width: Math.max(recApplyBtn.implicitWidth, Style.space(120))
            text: root.tr("cancel")
            onClicked: root.recordingDialogOpen = false
          }

          Button {
            id: recApplyBtn
            width: Math.max(implicitWidth, Style.space(120))
            text: root.tr("modal_record_apply")
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
          text: root.tr("modal_gestures_title")
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
          color: Color.foreground
        }

        Text {
          text: root.tr("modal_gestures_subtitle")
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: Color.muted
        }

        Row {
          width: parent.width
          spacing: Style.spacing.sm

          Button {
            width: Math.floor((parent.width - Style.spacing.sm) / 2)
            text: root.tr("modal_gestures_3_fingers")
            selected: root.candidateGestureFingers === 3
            onClicked: {
              root.candidateGestureFingers = 3
              root.checkCustomGesture(3)
            }
          }

          Button {
            width: Math.floor((parent.width - Style.spacing.sm) / 2)
            text: root.tr("modal_gestures_4_fingers")
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
              text: root.customGestureConflict ? root.customGestureConflictMessage : root.tr("modal_gestures_available", { fingers: root.candidateGestureFingers })
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
            id: gestCancelBtn
            width: Math.max(gestApplyBtn.implicitWidth, Style.space(120))
            text: root.tr("cancel")
            onClicked: root.customGesturesDialogOpen = false
          }

          Button {
            visible: root.customGestureConflict
            text: root.tr("modal_gestures_replace")
            fontSize: Style.font.caption
            tooltipText: "Disable the existing " + root.candidateGestureFingers + "-finger gesture and assign to OmaGuake"
            onClicked: {
              root.applyGesturesDirectly(true, root.candidateGestureFingers, true)
              root.customGesturesDialogOpen = false
            }
          }

          Button {
            id: gestApplyBtn
            width: Math.max(implicitWidth, Style.space(120))
            visible: !root.customGestureConflict
            text: root.tr("modal_gestures_apply")
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
            text: root.tr("modal_conflict_key_title")
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
            text: root.suggestedKeyConflictMessage || root.tr("modal_conflict_key_default_msg")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            color: Color.urgent
            verticalAlignment: Text.AlignVCenter
          }
        }

        Text {
          text: root.tr("modal_how_proceed")
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
            text: root.tr("modal_conflict_key_replace")
            selected: true
            tooltipText: "Disables the conflicting binding in Hyprland and assigns CTRL + SPACE to OmaGuake"
            onClicked: {
              root.keyConflictDialogOpen = false
              root.applyKeybindingDirectly("CTRL + SPACE", true)
            }
          }

          // Option 2: Record a different keybinding
          Button {
            width: parent.width
            text: root.tr("modal_conflict_key_choose_diff")
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
              text: root.tr("modal_conflict_key_alternatives")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
              anchors.verticalCenter: parent.verticalCenter
            }
            Repeater {
              model: root.keySuggestions
              delegate: Button {
                text: root.tr("modal_conflict_key_assign", { chord: modelData })
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
            text: root.tr("modal_cancel")
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
            text: root.tr("modal_conflict_gest_title")
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
            text: root.suggestedGestureConflictMessage || root.tr("modal_conflict_gest_default_msg")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            color: Color.urgent
            verticalAlignment: Text.AlignVCenter
          }
        }

        Text {
          text: root.tr("modal_how_proceed")
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
            text: root.tr("modal_conflict_gest_replace")
            selected: true
            tooltipText: "Disables the conflicting 3-finger gestures and assigns swipe down/up to OmaGuake"
            onClicked: {
              root.gestureConflictDialogOpen = false
              root.applyGesturesDirectly(true, 3, true)
            }
          }

          // Option 2: Choose 4-finger gestures
          Button {
            width: parent.width
            text: root.tr("modal_conflict_gest_4finger")
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
            text: root.tr("modal_cancel")
            onClicked: root.gestureConflictDialogOpen = false
          }
        }
      }
    }
  }

  // =========================================================================
  // MODAL 5: Language Selection Dialog
  // =========================================================================
  Rectangle {
    id: languageModalScrim
    visible: root.languageDialogOpen
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
      focus: root.languageDialogOpen

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.languageDialogOpen = false
          event.accepted = true
        }
      }
    }

    Rectangle {
      width: parent.width - Style.space(32)
      height: Math.min(parent.height - Style.space(40), langModalCol.implicitHeight + Style.space(32))
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.background
      border.color: Color.accent
      border.width: 1

      Column {
        id: langModalCol
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(12)

        Row {
          spacing: Style.spacing.sm
          Text {
            text: "🌐"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: root.tr("language_title")
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            color: Color.foreground
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          text: root.tr("language_desc")
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
          width: parent.width
          wrapMode: Text.WordWrap
        }

        ScrollView {
          width: parent.width
          height: Style.space(260)
          clip: true

          ListView {
            id: langListView
            anchors.fill: parent
            spacing: Style.space(4)
            model: root.languageList

            delegate: Button {
              width: langListView.width
              selected: root.selectedLanguage === modelData.code
              text: (root.selectedLanguage === modelData.code ? "✓  " : "    ") + (modelData.code === "" ? root.tr("lang_system") : modelData.label)
              fontSize: Style.font.bodySmall
              leftAlign: true
              onClicked: {
                root.selectedLanguage = modelData.code
                root.languageDialogOpen = false
              }
            }
          }
        }

        // Footer / Cancel
        Row {
          anchors.right: parent.right
          spacing: Style.spacing.sm

          Button {
            text: root.tr("cancel")
            onClicked: root.languageDialogOpen = false
          }
        }
      }
    }
  }
}
