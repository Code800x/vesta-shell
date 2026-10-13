pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../utils/SettingsMessages.js" as SettingsMessages

ContentSubsection {
    id: root
    title: Translation.tr("Interface theme")
    property string sourceChoice: Wallpapers.themeSource
    readonly property var selectedEntry: Wallpapers.themeEntryForSource(sourceChoice)
    readonly property var choices: {
        let values = [{name: Translation.tr("Last applied wallpaper"), code: ""}];
        HyprlandData.monitors.forEach((monitor, index) => values.push({
            name: Translation.tr("Monitor %1 (%2)").arg(index + 1).arg(monitor.name),
            code: monitor.name
        }));
        if (Wallpapers.themeSource && !values.some(value => value.code === Wallpapers.themeSource))
            values.push({name: Translation.tr("%1 (disconnected)").arg(Wallpapers.themeSource), code: Wallpapers.themeSource});
        return values;
    }
    Connections {
        target: Wallpapers
        function onThemeSourceChanged() { root.sourceChoice = Wallpapers.themeSource; }
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Choose which wallpaper provides the interface colors.")
        wrapMode: Text.WordWrap
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.small
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 12
        StyledText { text: Translation.tr("Color source") }
        StyledComboBox {
            Layout.fillWidth: true
            buttonIcon: "palette"
            textRole: "name"
            model: root.choices
            currentIndex: root.choices.findIndex(choice => choice.code === root.sourceChoice)
            enabled: !Wallpapers.applying
            onActivated: index => {
                if (index >= 0 && index < root.choices.length) {
                    root.sourceChoice = root.choices[index].code;
                    Wallpapers.lastThemeError = "";
                }
            }
        }
    }
    GridLayout {
        id: monitorGrid
        Layout.fillWidth: true
        Layout.topMargin: 8
        columns: width >= 600 ? 2 : 1
        columnSpacing: 10
        rowSpacing: 10
        Repeater {
            model: HyprlandData.monitors
            delegate: Rectangle {
                id: monitorCard
                required property var modelData
                required property int index
                readonly property var entry: Wallpapers.wallpaperForMonitor(modelData.name)
                readonly property bool video: /\.(mp4|webm|mkv|avi|mov)$/i.test(entry.path || "")
                readonly property string previewPath: video ? (entry.thumbnailPath || "") : (entry.path || "")
                readonly property bool usedInTheme: Wallpapers.themeSource
                    ? Wallpapers.themeSource === modelData.name
                    : !!entry.path && entry.path === Wallpapers.themePath
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: usedInTheme ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: monitorCard.previewPath
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !monitorCard.previewPath
                            text: monitorCard.video ? "movie" : "image"
                            iconSize: 28
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Monitor %1 (%2)").arg(monitorCard.index + 1).arg(monitorCard.modelData.name)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        MaterialSymbol {
                            visible: monitorCard.usedInTheme
                            text: "palette"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: monitorCard.usedInTheme ? Translation.tr("Used for the theme")
                            : monitorCard.entry.path ? Translation.tr("Wallpaper applied") : Translation.tr("No wallpaper configured")
                        color: monitorCard.usedInTheme ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: Translation.tr("Wallpapers stay on their monitors. Only the interface colors change.")
        wrapMode: Text.WordWrap
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 8
        StyledText {
            text: Translation.tr("Current palette")
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        Repeater {
            model: [Appearance.m3colors.m3primary, Appearance.m3colors.m3secondary,
                Appearance.m3colors.m3tertiary, Appearance.m3colors.m3surfaceContainerHigh]
            delegate: Rectangle {
                required property var modelData
                width: 16; height: 16; radius: 8
                color: modelData
                border.width: 1
                border.color: Appearance.colors.colOutline
            }
        }
        Item { Layout.fillWidth: true }
    }
    Flow {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 8
        RippleButtonWithIcon {
            materialIcon: "restart_alt"
            mainText: Translation.tr("Restore automatic")
            enabled: !Wallpapers.applying && !!Wallpapers.themeEntryForSource("").path
            onClicked: {
                root.sourceChoice = "";
                Wallpapers.applyThemeSource("");
            }
        }
        RippleButtonWithIcon {
            materialIcon: "palette"
            mainText: Wallpapers.applying ? Translation.tr("Applying...") : Translation.tr("Apply theme")
            enabled: !Wallpapers.applying && !!root.selectedEntry.path
            onClicked: Wallpapers.applyThemeSource(root.sourceChoice)
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: Wallpapers.lastThemeError.length > 0
        text: SettingsMessages.translate(Wallpapers.lastThemeError, Translation.tr)
        color: Appearance.colors.colError
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
