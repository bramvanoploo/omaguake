import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "i18n.js" as I18n

PanelWindow {
  id: root

  property bool open: false
  property string language: ""

  function tr(key) {
    var _ = root.language
    return I18n.t(key)
  }

  signal canceled()
  signal confirmed()

  visible: open
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "omaguake-dependency-dialog"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  property int selectedIndex: 1 // 0 = Cancel, 1 = Install

  onOpenChanged: {
    if (open) {
      selectedIndex = 1
      dialogCatcher.forceActiveFocus()
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.75)

    MouseArea {
      anchors.fill: parent
      onClicked: root.canceled()
    }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(48), Style.space(500))
      height: card.contentTopInset + card.contentBottomInset + contentColumn.implicitHeight
      anchors.centerIn: parent
      color: Color.background
      borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
      padding: Style.space(26)
      radius: Style.cornerRadius

      MouseArea {
        anchors.fill: parent
        onClicked: {} // Block clicks inside card from closing
      }

      Item {
        id: dialogCatcher
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: root.open

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.canceled()
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.selectedIndex = (root.selectedIndex === 0 ? 1 : 0)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (root.selectedIndex === 0) {
              root.canceled()
            } else {
              root.confirmed()
            }
            event.accepted = true
          }
        }

        Column {
          id: contentColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(18)

          // Header Row
          Row {
            spacing: Style.space(16)
            anchors.left: parent.left
            anchors.right: parent.right

            // Icon Badge
            BorderSurface {
              width: Style.space(46)
              height: Style.space(46)
              radius: Style.cornerRadius > 0 ? 8 : 2
              color: Util.alpha(Color.accent, 0.12)
              borderSpec: Border.flat(Util.alpha(Color.accent, 0.35), Style.normalBorderWidth)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.centerIn: parent
                text: "\uf489"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.heading * 1.3
              }
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                text: root.tr("dep_dialog_title")
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                font.weight: Font.DemiBold
              }

              Text {
                text: root.tr("dep_dialog_subtitle")
                color: Util.alpha(Color.foreground, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          // Information & Package Spec Surface
          BorderSurface {
            width: parent.width
            implicitHeight: innerCol.implicitHeight + Style.space(24)
            radius: Style.cornerRadius > 0 ? 6 : 0
            color: Util.alpha(Color.foreground, 0.04)
            borderSpec: Border.flat(Util.alpha(Color.foreground, 0.12), Style.normalBorderWidth)
            padding: Style.space(12)

            Column {
              id: innerCol
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: "\uf187"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: "qmltermwidget"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.weight: Font.Bold
                  anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                  width: Style.space(10)
                }

                // Repo Pill
                BorderSurface {
                  implicitWidth: repoText.implicitWidth + Style.space(12)
                  implicitHeight: repoText.implicitHeight + Style.space(6)
                  radius: Style.cornerRadius > 0 ? 4 : 0
                  color: Util.alpha(Color.accent, 0.12)
                  borderSpec: Border.flat(Util.alpha(Color.accent, 0.28), Style.normalBorderWidth)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: repoText
                    anchors.centerIn: parent
                    text: root.tr("dep_dialog_repo")
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.weight: Font.Medium
                  }
                }
              }

              Text {
                width: parent.width
                text: root.tr("dep_dialog_desc")
                color: Util.alpha(Color.foreground, 0.75)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                lineHeight: 1.25
              }
            }
          }

          // Main Prompt Text
          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: root.tr("dep_dialog_prompt")
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: Font.Medium
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: root.tr("dep_dialog_subtext")
              color: Util.alpha(Color.foreground, 0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }

          // Buttons Row
          Row {
            anchors.right: parent.right
            spacing: Style.space(12)

            // Cancel Button (index 0)
            BorderSurface {
              readonly property bool selected: root.selectedIndex === 0
              readonly property bool hovered: cancelMouse.containsMouse
              width: Style.space(105)
              height: Style.space(36)
              color: (selected || hovered) ? Util.alpha(Color.foreground, 0.12) : "transparent"
              borderSpec: Border.flat((selected || hovered) ? Color.accent : Util.alpha(Color.foreground, 0.35), Style.normalBorderWidth)
              radius: Style.cornerRadius > 0 ? 4 : 0

              Behavior on color { ColorAnimation { duration: 120 } }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(6)

                Text {
                  text: root.tr("dep_dialog_cancel")
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Medium
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: "Esc"
                  color: Util.alpha(Color.foreground, 0.45)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption * 0.85
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: cancelMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = 0
                onClicked: root.canceled()
              }
            }

            // Install Button (index 1)
            BorderSurface {
              readonly property bool selected: root.selectedIndex === 1
              readonly property bool hovered: installMouse.containsMouse
              width: Style.space(135)
              height: Style.space(36)
              color: (selected || hovered) ? Color.accent : Util.alpha(Color.accent, 0.88)
              borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
              radius: Style.cornerRadius > 0 ? 4 : 0

              Behavior on color { ColorAnimation { duration: 120 } }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(6)

                Text {
                  text: "\uf019"
                  color: Color.background || "#0c0d13"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: root.tr("dep_dialog_install")
                  color: Color.background || "#0c0d13"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: "↵"
                  color: Util.alpha(Color.background || "#0c0d13", 0.6)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption * 0.9
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: installMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = 1
                onClicked: root.confirmed()
              }
            }
          }
        }
      }
    }
  }
}
