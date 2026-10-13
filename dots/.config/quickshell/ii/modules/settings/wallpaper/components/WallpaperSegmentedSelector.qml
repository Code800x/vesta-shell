import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Exclusively selected options; inherits the current Material palette.
ColumnLayout {
    id: root
    property var options: []
    property string selectedCode: ""
    property bool interactive: true
    signal optionSelected(string code)
    spacing: 6
    Flow {
        Layout.fillWidth: true
        width: parent.width
        spacing: 8
        Repeater {
            model: root.options
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool active: modelData.code === root.selectedCode
                implicitWidth: chipRow.implicitWidth + 26
                implicitHeight: 36
                radius: height / 2
                color: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                border.width: active ? 1 : 0
                border.color: Appearance.colors.colPrimary
                opacity: root.interactive ? 1 : 0.55
                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: chip.active ? "radio_button_checked" : "radio_button_unchecked"
                        iconSize: 17
                        color: chip.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: chip.modelData.name
                        color: chip.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                HoverHandler { cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler {
                    enabled: root.interactive
                    onTapped: root.optionSelected(chip.modelData.code)
                }
            }
        }
    }
}
