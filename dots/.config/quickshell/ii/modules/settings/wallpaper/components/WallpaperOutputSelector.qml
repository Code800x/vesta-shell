import QtQuick
import "../../utils/SettingsMessages.js" as SettingsMessages
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
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

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        StyledText {
            text: Translation.tr("Apply wallpaper to")
            color: Appearance.colors.colOnSurface
        }
        StyledComboBox {
            Layout.fillWidth: true
            buttonIcon: "desktop_windows"
            textRole: "name"
            model: root.options
            currentIndex: root.options.findIndex(option => option.code === Wallpapers.selectedOutput)
            enabled: !Wallpapers.applying && Wallpapers.outputNames.length > 0
            onActivated: index => {
                if (index >= 0 && index < root.options.length) {
                    Wallpapers.selectedOutput = root.options[index].code;
                    Wallpapers.lastApplyError = "";
                }
            }
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
