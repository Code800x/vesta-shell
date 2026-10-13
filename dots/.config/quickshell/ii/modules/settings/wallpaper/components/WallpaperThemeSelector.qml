pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../utils/SettingsMessages.js" as SettingsMessages

ContentSubsection {
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
    title: Translation.tr("Interface theme · Dynamic colors")
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
    StyledText {
        Layout.topMargin: 8
        text: Translation.tr("Color source")
        color: Appearance.colors.colOnSurface
    }
    SegmentedChoice {
        Layout.fillWidth: true
        options: root.choices
        selectedCode: root.sourceChoice
        interactive: !Wallpapers.applying
        onOptionSelected: code => {
            root.sourceChoice = code;
            Wallpapers.lastThemeError = "";
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 12
        spacing: 8
        MaterialSymbol { text: "desktop_windows"; iconSize: 20; color: Appearance.colors.colPrimary }
        StyledText { text: Translation.tr("Monitors"); font.pixelSize: Appearance.font.pixelSize.normal }
        Item { Layout.fillWidth: true }
        StyledText {
            text: Translation.tr("Select a monitor to use its wallpaper colors")
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
    GridLayout {
        id: monitorGrid
        Layout.fillWidth: true
        Layout.topMargin: 8
        columns: width >= 600 ? 2 : 1
        columnSpacing: 12
        rowSpacing: 12
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
                Layout.preferredHeight: 242
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                border.width: usedInTheme ? 2 : 1
                border.color: usedInTheme ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                Behavior on border.color { ColorAnimation { duration: 180 } }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle {
                            width: 30; height: 30; radius: 7
                            color: monitorCard.usedInTheme ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                            StyledText {
                                anchors.centerIn: parent
                                text: String(monitorCard.index + 1)
                                color: monitorCard.usedInTheme ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText { text: Translation.tr("Monitor %1").arg(monitorCard.index + 1) }
                            StyledText {
                                Layout.fillWidth: true
                                text: monitorCard.modelData.name
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        MaterialSymbol {
                            visible: monitorCard.usedInTheme
                            text: "check_circle"
                            iconSize: 22
                            color: Appearance.colors.colPrimary
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.small
                        clip: true
                        color: Appearance.colors.colLayer1
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
                            iconSize: 32
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            width: 28; height: 28; radius: 7
                            visible: monitorCard.usedInTheme
                            color: Appearance.colors.colPrimaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "palette"
                                iconSize: 17
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }
                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignHCenter
                        materialIcon: monitorCard.usedInTheme ? "check" : "palette"
                        mainText: monitorCard.usedInTheme ? Translation.tr("Current theme source") : Translation.tr("Use for interface theme")
                        enabled: !Wallpapers.applying && !!monitorCard.entry.path && !monitorCard.usedInTheme
                        onClicked: {
                            root.sourceChoice = monitorCard.modelData.name;
                            Wallpapers.applyThemeSource(monitorCard.modelData.name);
                        }
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
            text: Translation.tr("Extracted color palette")
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        Repeater {
            model: [Appearance.m3colors.m3primary, Appearance.m3colors.m3secondary,
                Appearance.m3colors.m3tertiary, Appearance.m3colors.m3surfaceContainerHigh]
            delegate: Rectangle {
                required property var modelData
                width: 30; height: 30; radius: 15
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
