
import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

import "./components" as SettingsComponents

ContentPage {
    id: root

    forceWidth: true

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

            color:
                Appearance.colors.colOnSurfaceVariant

            font.pixelSize:
                Appearance.font.pixelSize.small
        }
    }

    SettingsComponents.WallpaperBrowser {
        Layout.fillWidth: true
    }

    SettingsComponents.LiveWallpaperOnlineBrowser {
        Layout.fillWidth: true
    }

    SettingsComponents.LiveWallpaperBrowser {
        Layout.fillWidth: true
    }
}
