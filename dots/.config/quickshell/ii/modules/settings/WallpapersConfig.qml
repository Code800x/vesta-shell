import "utils/SettingsMessages.js" as SettingsMessages
import QtQuick
import qs.services
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

import "./wallpaper/views" as WallpaperViews

ContentPage {
    id: root

    forceWidth: true

    // 0 = Wallpapers normais
    // 1 = Live Wallpapers
    // 2 = Meus Wallpapers
    property int activeTab: 0

    ContentSection {
        Layout.fillWidth: true

        icon: "wallpaper"
        title: Translation.tr("Wallpaper manager")

        StyledText {
            Layout.fillWidth: true

            text: Translation.tr("Browse, select and apply static or live wallpapers directly from Vesta Shell.")

            wrapMode: Text.WordWrap

            color: Appearance.colors.colOnSurfaceVariant

            font.pixelSize: Appearance.font.pixelSize.small
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            spacing: 8

            Repeater {
                model: [
                    {
                        title: Translation.tr("Static wallpapers"),
                        icon: "image"
                    },
                    {
                        title: Translation.tr("Live wallpapers"),
                        icon: "animated_images"
                    },
                    {
                        title: Translation.tr("My wallpapers"),
                        icon: "folder_open"
                    }
                ]

                delegate: Rectangle {
                    id: tabButton

                    required property int index
                    required property var modelData

                    readonly property bool selected:
                        root.activeTab === index

                    Layout.fillWidth: true
                    Layout.preferredHeight: 44

                    radius: Appearance.rounding.small

                    color: selected
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer2

                    border.width: selected ? 1 : 0
                    border.color: Appearance.colors.colPrimary

                    Behavior on color {
                        ColorAnimation {
                            duration: 160
                        }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: tabButton.modelData.icon
                            iconSize: 20

                            color: tabButton.selected
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            text: tabButton.modelData.title

                            color: tabButton.selected
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnSurfaceVariant

                            font.pixelSize:
                                Appearance.font.pixelSize.normal
                        }
                    }

                    HoverHandler {
                        id: hoverHandler
                        cursorShape: Qt.PointingHandCursor
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius

                        color: Appearance.colors.colPrimary

                        opacity: hoverHandler.hovered
                            ? 0.08
                            : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 140
                            }
                        }
                    }

                    TapHandler {
                        onTapped: root.activeTab = tabButton.index
                    }
                }
            }
        }
    }

    // Aba 1: wallpapers estáticos
    // O componente permanece instanciado ao trocar de aba.
    WallpaperViews.WallpaperBrowser {
        Layout.fillWidth: true
        visible: root.activeTab === 0
    }

    // Aba 2: explorar wallpapers animados online.
    WallpaperViews.LiveWallpaperOnlineBrowser {
        Layout.fillWidth: true
        visible: root.activeTab === 1
    }

    // Aba 3: biblioteca local e importação manual de vídeos.
    WallpaperViews.LocalWallpaperLibrary {
        Layout.fillWidth: true
        visible: root.activeTab === 2
    }
}
