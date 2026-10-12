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
    property bool generatingThumbnails: false
    property int missingThumbnails: 0
    property int currentPage: 0
    readonly property var pageTitles: ["Wallpapers estáticos", "Live Wallpapers", "Carregar vídeo"]
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
                root.generatingThumbnails = !!data.generating;
                root.missingThumbnails = Number(data.missing || 0);
                if (!data.ffmpeg_available && root.missingThumbnails > 0)
                    root.feedback = "Instale o FFmpeg para gerar miniaturas de imagens e vídeos.";
            } catch (e) {
                root.feedback = "Resposta inválida ao consultar os wallpapers locais.";
            }
        }
    }

    Timer {
        interval: 2200
        repeat: true
        running: root.visible && root.generatingThumbnails
        onTriggered: root.refresh()
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            RippleButtonWithIcon {
                materialIcon: "chevron_left"
                mainText: "Anterior"
                enabled: root.currentPage > 0
                onClicked: root.currentPage = Math.max(0, root.currentPage - 1)
            }
            Item { Layout.fillWidth: true }
            MaterialSymbol {
                text: root.currentPage === 0 ? "image" : (root.currentPage === 1 ? "animated_images" : "video_library")
                iconSize: 24
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: root.pageTitles[root.currentPage]
                font.pixelSize: Appearance.font.pixelSize.normal
            }
            Item { Layout.fillWidth: true }
            RippleButtonWithIcon {
                materialIcon: "chevron_right"
                mainText: "Próxima"
                enabled: root.currentPage < 2
                onClicked: root.currentPage = Math.min(2, root.currentPage + 1)
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            Repeater {
                model: root.pageTitles
                delegate: Item {
                    id: pageIndicator
                    required property int index
                    width: 26
                    height: 12

                    Rectangle {
                        anchors.centerIn: parent
                        width: root.currentPage === pageIndicator.index ? 24 : 8
                        height: 8
                        radius: height / 2
                        color: root.currentPage === pageIndicator.index
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOutlineVariant
                        Behavior on width { NumberAnimation { duration: 160 } }
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }

                    TapHandler {
                        onTapped: root.currentPage = pageIndicator.index
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: "Biblioteca: " + root.libraryDirectory
            visible: root.currentPage !== 2
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

        // Um único espaço de conteúdo: só a página selecionada aparece.
        // As listas continuam separadas e com rolagem própria.
        Item {
            id: carouselViewport
            Layout.fillWidth: true
            Layout.preferredHeight: 3 * 128 + 2 * 10 + 42
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 10
                visible: root.currentPage === 0
                RowLayout {
                    Layout.fillWidth: true
                    MaterialSymbol { text: "image"; iconSize: 22 }
                    StyledText { text: "Wallpapers estáticos" }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: root.images.length + " imagens"
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    RippleButtonWithIcon {
                        materialIcon: "refresh"
                        mainText: "Atualizar"
                        enabled: !root.scanning
                        onClicked: root.refresh()
                    }
                }
            Flickable {
                id: imagesScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
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
                            required property int index
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
                                source: (Math.floor(index / 3) * 138 < imagesScroll.contentY + imagesScroll.height + 276
                                    && Math.floor(index / 3) * 138 + 128 > imagesScroll.contentY - 276
                                    && root.currentPage === 0 && imageCard.modelData.thumbnail)
                                    ? "file://" + encodeURI(imageCard.modelData.thumbnail) : ""
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
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 10
                visible: root.currentPage === 1
                RowLayout {
                    Layout.fillWidth: true
                    MaterialSymbol { text: "animated_images"; iconSize: 22 }
                    StyledText { text: "Live Wallpapers" }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: root.videos.length + " vídeos"
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    RippleButtonWithIcon {
                        materialIcon: "refresh"
                        mainText: "Atualizar"
                        enabled: !root.scanning
                        onClicked: root.refresh()
                    }
                }
            Flickable {
                id: videosScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
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
                            required property int index
                            required property var modelData
                            Layout.preferredWidth: Math.max(0, (videosGrid.width - 2 * videosGrid.columnSpacing) / 3)
                            Layout.preferredHeight: 110
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            border.width: root.selectedPath === modelData.path ? 2 : 0
                            border.color: Appearance.colors.colPrimary
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: (Math.floor(videoCard.index / 3) * 120 < videosScroll.contentY + videosScroll.height + 240
                                    && Math.floor(videoCard.index / 3) * 120 + 110 > videosScroll.contentY - 240
                                    && root.currentPage === 1 && videoCard.modelData.thumbnail)
                                    ? "file://" + encodeURI(videoCard.modelData.thumbnail) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 360
                                sourceSize.height: 210
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 32
                                color: "#B8000000"
                                StyledText {
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    text: videoCard.modelData.name
                                    elide: Text.ElideRight
                                    color: "white"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "play_circle"
                                iconSize: 32
                                color: "white"
                            }
                            /*ColumnLayout {
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
                            */
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
            }

            // Seletor manual original, preservado integralmente.
            Loader {
                anchors.fill: parent
                active: root.currentPage === 2
                visible: root.currentPage === 2
                source: "LiveWallpaperBrowser.qml"
            }
        }
    }
}