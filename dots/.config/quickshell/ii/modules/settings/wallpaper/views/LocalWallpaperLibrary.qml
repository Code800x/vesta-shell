import "../../utils/SettingsMessages.js" as SettingsMessages
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
    title: Translation.tr("My wallpapers")
    icon: "folder_open"

    property var images: []
    property var videos: []
    property string selectedPath: ""
    property string feedback: ""
    property string pendingRemovalPath: ""
    property string pendingRemovalName: ""
    property bool removing: false

    function isActiveWallpaper(path) {
        const active = Wallpapers.wallpapers || [];
        return active.some(value => String(value).replace("file://", "") === path);
    }

    function requestRemoval(path, name) {
        if (!path || root.removing) return;
        if (root.isActiveWallpaper(path)) {
            root.feedback = Translation.tr("This wallpaper is currently in use. Apply another wallpaper before removing it.");
            return;
        }
        root.pendingRemovalPath = path;
        root.pendingRemovalName = name || "";
        removalDialog.open();
    }

    function removeConfirmed() {
        if (!root.pendingRemovalPath || root.removing) return;
        root.removing = true;
        root.feedback = "";
        const args = ["python3", root.scannerPath, "--trash", root.pendingRemovalPath];
        for (const path of Wallpapers.wallpapers || [])
            if (path) args.push(String(path).replace("file://", ""));
        trashProcess.command = args;
        trashProcess.running = true;
    }
    property bool scanning: false
    property bool loadedOnce: false
    property bool generatingThumbnails: false
    property int missingThumbnails: 0
    property int currentPage: 0
    readonly property var pageTitles: [Translation.tr("Static wallpapers"), Translation.tr("Live wallpapers"), Translation.tr("Load video")]
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
        if (!Wallpapers.applyToSelected(path)) return;
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

    Process {
        id: trashProcess
        running: false
        stdout: StdioCollector { id: trashOutput }
        stderr: StdioCollector { id: trashErrors }
        onExited: (exitCode, exitStatus) => {
            root.removing = false;
            if (exitCode === 0) {
                if (root.selectedPath === root.pendingRemovalPath)
                    root.selectedPath = "";
                root.feedback = Translation.tr("Wallpaper moved to trash.");
                root.pendingRemovalPath = "";
                root.refresh();
            } else {
                root.feedback = Translation.tr("Could not move wallpaper to trash.") + " " + trashErrors.text.trim();
            }
        }
    }

    // Follow the existing Vesta Material 3 confirmation popup pattern.
    Controls.Popup {
        id: removalDialog
        parent: Controls.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(420, parent ? parent.width - 32 : 420)
        modal: true
        focus: true
        padding: 22
        closePolicy: Controls.Popup.CloseOnEscape

        background: Rectangle {
            radius: Appearance.rounding.large
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.m3colors.m3outlineVariant
        }

        contentItem: ColumnLayout {
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    text: "delete_outline"
                    iconSize: 24
                    color: Appearance.m3colors.m3error
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Remove wallpaper")
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                    wrapMode: Text.WordWrap
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Move this wallpaper to the trash?")
                color: Appearance.m3colors.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.pendingRemovalName.length > 0
                text: root.pendingRemovalName
                color: Appearance.m3colors.m3onSurface
                wrapMode: Text.WrapAnywhere
                font.pixelSize: Appearance.font.pixelSize.small
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: removalDialog.close()
                }

                DialogButton {
                    buttonText: Translation.tr("Move to trash")
                    colText: Appearance.m3colors.m3error
                    onClicked: {
                        root.removeConfirmed();
                        removalDialog.close();
                    }
                }
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
                mainText: Translation.tr("Previous")
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
                mainText: Translation.tr("Next")
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
            text: SettingsMessages.translate("Biblioteca: " + root.libraryDirectory, Translation.tr)
            visible: root.currentPage !== 2
            elide: Text.ElideMiddle
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.feedback.length > 0
            text: SettingsMessages.translate(root.feedback, Translation.tr)
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
                    StyledText { text: Translation.tr("Static wallpapers")}
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: SettingsMessages.translate(root.images.length + " imagens", Translation.tr)
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    RippleButtonWithIcon {
                        materialIcon: "refresh"
                        mainText: Translation.tr("Refresh")
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
                        delegate: Loader {
                            id: imageCard
                            required property int index
                            required property var modelData
                            Layout.preferredWidth: Math.max(0, (imagesGrid.width - 2 * imagesGrid.columnSpacing) / 3)
                            Layout.preferredHeight: 128
                            Component.onCompleted: setSource("../components/WallpaperCard.qml", {
                                "wallpaper": { "thumb": "", "title": modelData.name || "" },
                                "local": true
                            })
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 5
                                width: 36
                                height: 36
                                radius: 9
                                // Solid Material surface keeps the action readable over bright wallpapers.
                                color: removeMouseimageCard.containsMouse
                                    ? Appearance.m3colors.m3errorContainer
                                    : Appearance.m3colors.m3surfaceContainerHigh
                                border.width: 1
                                border.color: removeMouseimageCard.containsMouse
                                    ? Appearance.m3colors.m3error
                                    : Appearance.m3colors.m3outlineVariant
                                z: 5

                                Behavior on color { ColorAnimation { duration: 140 } }
                                Behavior on border.color { ColorAnimation { duration: 140 } }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete_outline"
                                    iconSize: 23
                                    color: removeMouseimageCard.containsMouse
                                        ? Appearance.m3colors.m3onErrorContainer
                                        : Appearance.m3colors.m3error
                                }
                                MouseArea {
                                    id: removeMouseimageCard
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.removing
                                    onClicked: root.requestRemoval(imageCard.modelData.path, imageCard.modelData.name)
                                }
                            }
                            onLoaded: {
                                item.wallpaper = Qt.binding(() => ({
                                    thumb: (Math.floor(imageCard.index / 3) * 138 < imagesScroll.contentY + imagesScroll.height + 276
                                        && Math.floor(imageCard.index / 3) * 138 + 128 > imagesScroll.contentY - 276
                                        && root.currentPage === 0 && imageCard.modelData.thumbnail)
                                        ? "file://" + encodeURI(imageCard.modelData.thumbnail) : "",
                                    title: imageCard.modelData.name || ""
                                }));
                                item.local = true;
                                item.live = false;
                                item.localVideo = false;
                                item.selected = Qt.binding(() => root.selectedPath === imageCard.modelData.path);
                                item.activated.connect(() => root.applyPath(imageCard.modelData.path));
                            }
                        }
                    }
                }
            }
                StyledText {
                    visible: !root.scanning && root.images.length === 0
                    text: Translation.tr("No images found in the library.")
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
                    StyledText { text: Translation.tr("Live wallpapers")}
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: SettingsMessages.translate(root.videos.length + " vídeos", Translation.tr)
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    RippleButtonWithIcon {
                        materialIcon: "refresh"
                        mainText: Translation.tr("Refresh")
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
                        delegate: Loader {
                            id: videoCard
                            required property int index
                            required property var modelData
                            Layout.preferredWidth: Math.max(0, (videosGrid.width - 2 * videosGrid.columnSpacing) / 3)
                            Layout.preferredHeight: 110
                            Component.onCompleted: setSource("../components/WallpaperCard.qml", {
                                "wallpaper": { "thumb": "", "title": modelData.name || "" },
                                "local": true
                            })
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 5
                                width: 36
                                height: 36
                                radius: 9
                                // Solid Material surface keeps the action readable over bright wallpapers.
                                color: removeMousevideoCard.containsMouse
                                    ? Appearance.m3colors.m3errorContainer
                                    : Appearance.m3colors.m3surfaceContainerHigh
                                border.width: 1
                                border.color: removeMousevideoCard.containsMouse
                                    ? Appearance.m3colors.m3error
                                    : Appearance.m3colors.m3outlineVariant
                                z: 5

                                Behavior on color { ColorAnimation { duration: 140 } }
                                Behavior on border.color { ColorAnimation { duration: 140 } }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete_outline"
                                    iconSize: 23
                                    color: removeMousevideoCard.containsMouse
                                        ? Appearance.m3colors.m3onErrorContainer
                                        : Appearance.m3colors.m3error
                                }
                                MouseArea {
                                    id: removeMousevideoCard
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.removing
                                    onClicked: root.requestRemoval(videoCard.modelData.path, videoCard.modelData.name)
                                }
                            }
                            onLoaded: {
                                item.wallpaper = Qt.binding(() => ({
                                    thumb: (Math.floor(videoCard.index / 3) * 120 < videosScroll.contentY + videosScroll.height + 240
                                        && Math.floor(videoCard.index / 3) * 120 + 110 > videosScroll.contentY - 240
                                        && root.currentPage === 1 && videoCard.modelData.thumbnail)
                                        ? "file://" + encodeURI(videoCard.modelData.thumbnail) : "",
                                    title: videoCard.modelData.name || ""
                                }));
                                item.local = true;
                                item.live = false;
                                item.localVideo = true;
                                item.selected = Qt.binding(() => root.selectedPath === videoCard.modelData.path);
                                item.activated.connect(() => root.applyPath(videoCard.modelData.path));
                            }
                        }
                    }
                }
            }
                StyledText {
                    visible: !root.scanning && root.videos.length === 0
                    text: Translation.tr("No videos found in the library.")
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