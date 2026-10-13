import QtQuick
import "../../utils/SettingsMessages.js" as SettingsMessages
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root

    component SegmentedChoice: ColumnLayout {
        id: selector
        property var options: []
        property string selectedCode: ""
        property bool interactive: true
        signal optionSelected(string code)
        spacing: 6
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: selector.options
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool active: modelData.code === selector.selectedCode
                    implicitWidth: chipRow.implicitWidth + 26
                    implicitHeight: 36
                    radius: height / 2
                    color: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    border.width: active ? 1 : 0
                    border.color: Appearance.colors.colPrimary
                    opacity: selector.interactive ? 1 : 0.55
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
                    HoverHandler { cursorShape: selector.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler {
                        enabled: selector.interactive
                        onTapped: selector.optionSelected(chip.modelData.code)
                    }
                }
            }
        }
    }
    Layout.fillWidth: true
    spacing: 6
    readonly property var options: [{
        name: Wallpapers.outputNames.length === 2
            ? Translation.tr("Both monitors") : Translation.tr("All monitors"),
        code: ""
    }].concat(HyprlandData.monitors.map((monitor, index) => ({
        name: Translation.tr("Monitor %1 (%2)").arg(index + 1).arg(monitor.name),
        code: monitor.name
    })))

    StyledText {
        text: Translation.tr("Apply wallpaper to")
        color: Appearance.colors.colOnSurface
    }
    SegmentedChoice {
        Layout.fillWidth: true
        options: root.options
        selectedCode: Wallpapers.selectedOutput
        interactive: !Wallpapers.applying && Wallpapers.outputNames.length > 0
        onOptionSelected: code => {
            Wallpapers.selectedOutput = code;
            Wallpapers.lastApplyError = "";
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: !Wallpapers.selectedOutputAvailable
            ? Translation.tr("Select a connected monitor before applying a wallpaper.")
            : Wallpapers.lastApplyError.length > 0
                ? Translation.tr("Wallpaper could not be applied: %1").arg(SettingsMessages.translate(Wallpapers.lastApplyError, Translation.tr))
                : Translation.tr("The wallpaper will change only on the selected monitors. Choose the interface color source below.")
        wrapMode: Text.WordWrap
        color: !Wallpapers.selectedOutputAvailable || Wallpapers.lastApplyError.length > 0
            ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
