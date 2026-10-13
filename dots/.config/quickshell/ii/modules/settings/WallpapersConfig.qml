import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "./wallpaper/views" as WallpaperViews
import "./wallpaper/components" as WallpaperComponents

// Vesta: responsive Material layout. Keep the existing search, download,
// wallpaper application and theme services inside their original components.
ContentPage {
    id: root
    // Follow the same shared page sizing as ServicesConfig and GeneralConfig.
    forceWidth: true
    property int activeTab: 0

    ContentSection {
        Layout.fillWidth: true
        icon: "wallpaper"
        title: Translation.tr("Wallpapers · Vesta Shell")
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Manage wallpapers, explore your library and choose your interface colors.")
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    Component {
        id: libraryComponent
        ColumnLayout {
            id: libraryContent
            spacing: 12
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 58
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    Repeater {
                        model: [
                            { title: Translation.tr("Library"), icon: "image" },
                            { title: Translation.tr("Live wallpapers"), icon: "animated_images" },
                            { title: Translation.tr("My wallpapers"), icon: "folder_open" }
                        ]
                        delegate: Rectangle {
                            id: tab
                            required property int index
                            required property var modelData
                            readonly property bool selected: root.activeTab === index
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            implicitHeight: 42
                            radius: Appearance.rounding.small
                            color: selected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                            border.width: selected ? 1 : 0
                            border.color: Appearance.colors.colPrimary
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 5
                                MaterialSymbol {
                                    text: tab.modelData.icon
                                    iconSize: 17
                                    color: tab.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: tab.modelData.title
                                    elide: Text.ElideRight
                                    color: tab.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.activeTab = tab.index }
                        }
                    }
                }
            }
            WallpaperViews.WallpaperBrowser {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: root.activeTab === 0
            }
            WallpaperViews.LiveWallpaperOnlineBrowser {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: root.activeTab === 1
            }
            WallpaperViews.LocalWallpaperLibrary {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: root.activeTab === 2
            }
        }
    }

    Component {
        id: settingsComponent
        ColumnLayout {
            spacing: 14
            WallpaperComponents.WallpaperOutputSelector { Layout.fillWidth: true }
            WallpaperComponents.WallpaperThemeSelector { Layout.fillWidth: true }
        }
    }

    // Use ContentPage's existing sizing, spacing and scrolling behavior.
    Loader {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredHeight: item ? item.implicitHeight : 0
        sourceComponent: libraryComponent
    }

    Loader {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredHeight: item ? item.implicitHeight : 0
        sourceComponent: settingsComponent
    }
}
