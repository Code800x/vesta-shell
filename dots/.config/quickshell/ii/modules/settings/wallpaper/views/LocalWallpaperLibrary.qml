import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

ContentSection {
    id: root
    Layout.fillWidth: true
    title: "Meus Wallpapers"
    icon: "folder_open"

    property var images: []
    property var videos: []
    property string selectedPath: ""
    property string feedback: ""
    property bool scanning: false
    property bool loadedOnce: false
    readonly property string libraryDirectory: FileUtils.trimFileProtocol(Directories.pictures) + "/Wallpapers"
    readonly property string scannerPath: FileUtils.trimFileProtocol(Qt.resolvedUrl("../../../../scripts/wallpaper/local_library.py").toString())

    function refresh() {
        if (scanner.running) return;
        root.scanning = true;
        root.feedback = "";
        scanner.command = ["python3", root.scannerPath, root.libraryDirectory];
        scanner.running = true;
    }

    function applyPath(path) {
        if (!path) return;
        Wallpapers.apply(path);
        root.selectedPath = path;
        root.feedback = "Wallpaper enviado para aplicação.";
    }

    onVisibleChanged: {
        if (visible) refresh();
    }
    Component.onCompleted: {
        if (visible) refresh();
    }

    Process {
        id: scanner
        running: false
        stdout: StdioCollector { id: scanOutput }
        stderr: StdioCollector { id: scanErrors }
        onExited: (exitCode, exitStatus) => {
            root.scanning = false;
            if (exitCode !== 0) {
                root.feedback = "Falha ao listar wallpapers: " + scanErrors.text.trim();
                return;
            }
            try {
                const data = JSON.parse(scanOutput.text);
                root.images = Array.isArray(data.images) ? data.images : [];
                root.videos = Array.isArray(data.videos) ? data.videos : [];
                root.loadedOnce = true;
            } catch (e) {
                root.feedback = "Resposta inválida ao consultar os wallpapers locais.";
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 18

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14
                MaterialSymbol {
                    text: "video_library"
                    iconSize: 34
                    color: Appearance.colors.colPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    StyledText {
                        text: "Adicionar wallpaper de vídeo local"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Escolha vídeos MP4 ou WebM de uma pasta para aplicar como wallpaper animado."
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
                RippleButtonWithIcon {
                    materialIcon: "refresh"
                    mainText: root.scanning ? "Buscando..." : "Atualizar"
                    enabled: !root.scanning
                    onClicked: root.refresh()
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: "Biblioteca: " + root.libraryDirectory
            elide: Text.ElideMiddle
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.feedback.length > 0
            text: root.feedback
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnSurfaceVariant
        }

        RowLayout {
            Layout.fillWidth: true
            MaterialSymbol { text: "image"; iconSize: 24 }
            StyledText { text: "Wallpapers estáticos"; font.pixelSize: Appearance.font.pixelSize.normal }
            Item { Layout.fillWidth: true }
            StyledText { text: root.images.length + " imagens"; color: Appearance.colors.colOnSurfaceVariant }
        }

        Flickable {
            id: imagesScroll
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(imagesGrid.implicitHeight, 3 * 128 + 2 * 10)
            visible: root.images.length > 0
            clip: true
            contentWidth: width
            contentHeight: imagesGrid.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Controls.ScrollBar.vertical: Controls.ScrollBar {
                policy: Controls.ScrollBar.AsNeeded
            }

            GridLayout {
                id: imagesGrid
                width: imagesScroll.width
                columns: 3
                columnSpacing: 10
                rowSpacing: 10
                Repeater {
                    model: root.images
                    delegate: Rectangle {
                        id: imageCard
                        required property var modelData
                        Layout.preferredWidth: Math.max(0, (imagesGrid.width - 2 * imagesGrid.columnSpacing) / 3)
                        Layout.preferredHeight: 128
                        radius: Appearance.rounding.small
                        clip: true
                        color: Appearance.colors.colLayer2
                        border.width: root.selectedPath === modelData.path ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                        Image {
                            anchors.fill: parent
                            source: "file://" + encodeURI(imageCard.modelData.path)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 320
                            sourceSize.height: 180
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 34
                            color: "#B8000000"
                            StyledText {
                                anchors.fill: parent
                                anchors.margins: 8
                                text: imageCard.modelData.name
                                elide: Text.ElideRight
                                color: "white"
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                        TapHandler { onTapped: root.applyPath(imageCard.modelData.path) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }
        StyledText {
            visible: !root.scanning && root.images.length === 0
            text: "Nenhuma imagem encontrada na biblioteca."
            color: Appearance.colors.colOnSurfaceVariant
        }

        RowLayout {
            Layout.fillWidth: true
            MaterialSymbol { text: "animated_images"; iconSize: 24 }
            StyledText { text: "Live Wallpapers"; font.pixelSize: Appearance.font.pixelSize.normal }
            Item { Layout.fillWidth: true }
            StyledText { text: root.videos.length + " vídeos"; color: Appearance.colors.colOnSurfaceVariant }
        }
        Flickable {
            id: videosScroll
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(videosGrid.implicitHeight, 3 * 110 + 2 * 10)
            visible: root.videos.length > 0
            clip: true
            contentWidth: width
            contentHeight: videosGrid.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Controls.ScrollBar.vertical: Controls.ScrollBar {
                policy: Controls.ScrollBar.AsNeeded
            }

            GridLayout {
                id: videosGrid
                width: videosScroll.width
                columns: 3
                columnSpacing: 10
                rowSpacing: 10
                Repeater {
                    model: root.videos
                    delegate: Rectangle {
                        id: videoCard
                        required property var modelData
                        Layout.preferredWidth: Math.max(0, (videosGrid.width - 2 * videosGrid.columnSpacing) / 3)
                        Layout.preferredHeight: 110
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        border.width: root.selectedPath === modelData.path ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - 20
                            spacing: 6
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "play_circle"
                                iconSize: 32
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: videoCard.modelData.name
                                elide: Text.ElideMiddle
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                        TapHandler { onTapped: root.applyPath(videoCard.modelData.path) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }
        StyledText {
            visible: !root.scanning && root.videos.length === 0
            text: "Nenhum vídeo encontrado na biblioteca."
            color: Appearance.colors.colOnSurfaceVariant
        }

        // Preserva o seletor manual existente, inclusive o diretório customizado.
        Loader {
            Layout.fillWidth: true
            active: true
            source: "LiveWallpaperBrowser.qml"
        }
    }
}
