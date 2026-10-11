
import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

import "./components" as SettingsComponents

ContentPage {
    id: root

    forceWidth: true

    // 0 = Wallpapers normais
    // 1 = Live Wallpapers
    property int activeTab: 0

    ContentSection {
        Layout.fillWidth: true

        icon: "wallpaper"
        title: "Gerenciador de Wallpapers"

        StyledText {
            Layout.fillWidth: true

            text:
                "Explore, selecione e aplique papéis de " +
                "parede estáticos ou animados diretamente " +
                "pelo Vesta Shell."

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
                        title: "Wallpapers normais",
                        icon: "image"
                    },
                    {
                        title: "Live Wallpapers",
                        icon: "animated_images"
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
    SettingsComponents.WallpaperBrowser {
        Layout.fillWidth: true
        visible: root.activeTab === 0
    }

    // Aba 2: wallpapers animados
    // Os dois navegadores compartilham a mesma aba.
    SettingsComponents.LiveWallpaperOnlineBrowser {
        Layout.fillWidth: true
        visible: root.activeTab === 1
    }

    SettingsComponents.LiveWallpaperBrowser {
        Layout.fillWidth: true
        visible: root.activeTab === 1
    }
}
