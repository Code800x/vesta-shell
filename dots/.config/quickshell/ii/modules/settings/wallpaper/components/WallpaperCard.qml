import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets

// Card visual compartilhado. O navegador controla seleção, cache e ações.
Item {
    id: root

    required property var wallpaper
    property bool selected: false
    property bool cached: false
    property bool active: false
    property bool busy: false
    property bool live: false
    property bool local: false
    property bool localVideo: false
    signal activated()

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: root.local ? 0 : 4
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        clip: true

        // A mesma máscara arredondada é usada na imagem E na tarja.
        Rectangle {
            id: roundedMask
            anchors.fill: parent
            radius: card.radius
            color: "white"
            visible: false
            layer.enabled: true
        }

        // Agrupa a miniatura e a tarja em uma única camada mascarada.
        Item {
            id: imageContent
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: roundedMask
            }

            Image {
                id: thumbnail
                anchors.fill: parent
                source: root.wallpaper.thumb || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 340
                sourceSize.height: 240
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.local ? (root.localVideo ? 32 : 34) : root.live ? 34 : 30
                color: root.live ? "#AA000000" : "#99000000"
                StyledText {
                    anchors.fill: parent
                    anchors.margins: root.local ? 8 : root.live ? 7 : 0
                    text: root.local ? (root.wallpaper.title || "") : root.live ? (root.wallpaper.title || "") : (root.wallpaper.resolution || "")
                    color: "white"
                    elide: Text.ElideRight
                    horizontalAlignment: (root.local || root.live) ? Text.AlignLeft : Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: !root.local && (root.live
                ? thumbnail.status !== Image.Ready
                : thumbnail.status === Image.Loading)
            text: root.live ? "movie" : "image"
            iconSize: 28
            color: Appearance.colors.colOnSurface
        }
        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: Appearance.colors.colPrimary
            opacity: root.selected ? 0.18 : hoverHandler.hovered ? 0.12 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: "transparent"
            border.width: root.selected ? 3 : 0
            border.color: Appearance.colors.colPrimary
        }
        Rectangle {
            anchors.top: parent.top
            anchors.left: root.live ? undefined : parent.left
            anchors.right: root.live ? parent.right : undefined
            anchors.margins: root.live ? 7 : 6
            visible: root.cached && !root.local
            width: cacheBadge.implicitWidth + (root.live ? 16 : 14)
            height: 25
            radius: Appearance.rounding.small
            color: root.active
                ? Appearance.colors.colPrimary
                : Appearance.colors.colPrimaryContainer
            Row {
                id: cacheBadge
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    text: root.active ? "check_circle" : "download_done"
                    iconSize: 14
                    color: root.active
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    text: root.active ? "Em uso" : "Já baixado"
                    color: root.active
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnPrimaryContainer
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            width: 28
            height: 28
            radius: 14
            visible: root.selected && !root.live && !root.local
            color: Appearance.colors.colPrimary
            MaterialSymbol {
                anchors.centerIn: parent
                text: "check"
                iconSize: 18
                color: Appearance.colors.colOnPrimary
            }
        }
        MaterialSymbol {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            visible: root.selected && root.live && !root.local
            text: "check_circle"
            iconSize: 25
            color: Appearance.colors.colPrimary
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: root.local && root.localVideo
            text: "play_circle"
            iconSize: 32
            color: "white"
        }
        MaterialSymbol {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            visible: root.local && root.selected
            text: "check_circle"
            iconSize: 25
            color: Appearance.colors.colPrimary
        }
        HoverHandler {
            id: hoverHandler
            enabled: !root.busy
            cursorShape: root.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
        }
        TapHandler {
            enabled: !root.busy
            onTapped: root.activated()
        }
    }
}
