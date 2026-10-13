import "../../utils/SettingsMessages.js" as SettingsMessages
import QtQuick

import QtQuick.Layouts

import QtQuick.Dialogs

import Qt.labs.folderlistmodel
import Qt.labs.settings

import Quickshell



import qs.modules.common

import qs.modules.common.functions

import qs.modules.common.widgets

import qs.services



ContentSection {

    id: root



    title: Translation.tr("Live wallpapers")

    icon: "animated_images"

    Layout.fillWidth: true



    readonly property string defaultDirectory:
        FileUtils.trimFileProtocol(Directories.pictures) + "/Wallpapers"
    property string folderUrl:
        "file://" + encodeURI(directorySettings.lastDirectory || defaultDirectory)

    Settings {
        id: directorySettings
        category: "VestaShellLiveWallpapers"
        property string lastDirectory: ""
    }



    property string selectedPath: ""

    property string selectedName: ""



    property string feedback: ""

    property bool hasError: false



    readonly property var supportedExtensions: [

        "mp4",

        "webm"

    ]



    function openDirectory(path) {

        const cleanPath = path.trim();



        if (cleanPath.length === 0) {

            root.hasError = true;

            root.feedback = "Informe um diretório válido.";

            return;

        }



        if (!cleanPath.startsWith("/")) {

            root.hasError = true;

            root.feedback =

                "Informe o caminho absoluto do diretório.";

            return;

        }



        root.selectedPath = "";

        root.selectedName = "";

        root.hasError = false;

        root.feedback = "";



        root.folderUrl = "file://" + encodeURI(cleanPath);
        directorySettings.lastDirectory = cleanPath;

    }



    function selectVideo(index) {

        const path = folderModel.get(

            index,

            "filePath"

        );



        const name = folderModel.get(

            index,

            "fileName"

        );



        if (!path || path.length === 0)

            return;



        root.selectedPath = path;

        root.selectedName = name;

        root.hasError = false;

        root.feedback = "";

        // Na terceira página, o botão inferior fica fora da área visível.
        // Um toque seleciona e solicita a aplicação imediatamente.
        root.applyVideo();

    }



    function applyVideo() {

        if (root.selectedPath.length === 0)

            return;



        Wallpapers.apply(root.selectedPath);



        root.hasError = false;

        root.feedback =

            "Vídeo enviado ao gerenciador de wallpapers. A reprodução e a geração de cores serão realizadas pelo switchwall.sh.";

    }



    // Seletor nativo de pastas. O botão Abrir não deve apenas reler o campo.

    FolderDialog {

        id: directoryPicker

        title: Translation.tr("Select video folder")

        currentFolder: root.folderUrl

        onAccepted: {

            const chosen = decodeURIComponent(

                selectedFolder.toString().substring(7)

            );

            directoryField.text = chosen;

            root.openDirectory(chosen);

        }

    }



    FolderListModel {

        id: folderModel



        folder: root.folderUrl



        nameFilters: [

            "*.mp4",

            "*.webm"

        ]



        caseSensitive: false

        showDirs: false

        showFiles: true

        showDotAndDotDot: false

        showOnlyReadable: true



        sortField: FolderListModel.Name

    }



    ColumnLayout {

        Layout.fillWidth: true

        spacing: 12



        StyledText {

            Layout.fillWidth: true



            text: Translation.tr("Choose a local video to use as a live wallpaper. Videos will loop without audio using mpvpaper.")



            wrapMode: Text.WordWrap



            color:

                Appearance.colors.colOnSurfaceVariant



            font.pixelSize:

                Appearance.font.pixelSize.small

        }



        // Diretório da biblioteca

        RowLayout {

            Layout.fillWidth: true

            spacing: 8



            MaterialTextField {

                id: directoryField



                Layout.fillWidth: true

                Layout.preferredHeight: 48



                placeholderText: Translation.tr("Video directory")



                text: directorySettings.lastDirectory || root.defaultDirectory



                onAccepted: {

                    root.openDirectory(text);

                }

            }



            RippleButtonWithIcon {

                Layout.preferredHeight: 48



                materialIcon: "folder_open"

                mainText: Translation.tr("Open")



                buttonRadius:

                    Appearance.rounding.small



                onClicked: directoryPicker.open()

            }

        }



        RowLayout {

            Layout.fillWidth: true

            spacing: 8



            MaterialSymbol {

                text: "video_library"

                iconSize: 20



                color:

                    Appearance.colors.colOnSurface

            }



            StyledText {

                text: SettingsMessages.translate(folderModel.count +

                    (folderModel.count === 1

                        ? " vídeo encontrado"

                        : " vídeos encontrados"), Translation.tr)



                color:

                    Appearance.colors.colOnSurface



                font.pixelSize:

                    Appearance.font.pixelSize.small

            }



            Item {

                Layout.fillWidth: true

            }



            StyledText {

                text: "MP4 · WebM"



                color:

                    Appearance.colors.colOnSurfaceVariant



                font.pixelSize:

                    Appearance.font.pixelSize.smaller

            }

        }



        // Biblioteca

        Rectangle {

            Layout.fillWidth: true

            Layout.preferredHeight: 300



            radius:

                Appearance.rounding.small



            color:

                Appearance.colors.colLayer1



            clip: true



            ListView {

                id: videoList



                anchors.fill: parent

                anchors.margins: 6



                clip: true

                spacing: 4



                model: folderModel



                boundsBehavior:

                    Flickable.StopAtBounds



                delegate: Rectangle {

                    id: videoDelegate



                    required property int index



                    readonly property string videoPath:

                        folderModel.get(

                            index,

                            "filePath"

                        ) || ""



                    readonly property string videoName:

                        folderModel.get(

                            index,

                            "fileName"

                        ) || ""



                    readonly property bool selected:

                        root.selectedPath.length > 0 &&

                        root.selectedPath === videoPath



                    width: videoList.width

                    height: 58



                    radius:

                        Appearance.rounding.small



                    color: selected

                        ? Appearance.colors.colPrimaryContainer

                        : hoverHandler.hovered

                            ? Appearance.colors.colLayer2

                            : "transparent"



                    Behavior on color {

                        ColorAnimation {

                            duration: 140

                        }

                    }



                    RowLayout {

                        anchors.fill: parent

                        anchors.leftMargin: 12

                        anchors.rightMargin: 12



                        spacing: 12



                        MaterialSymbol {

                            text: "movie"

                            iconSize: 25



                            color: videoDelegate.selected

                                ? Appearance.colors.colPrimary

                                : Appearance.colors.colOnSurface

                        }



                        ColumnLayout {

                            Layout.fillWidth: true

                            spacing: 2



                            StyledText {

                                Layout.fillWidth: true



                                text:

                                    videoDelegate.videoName



                                elide: Text.ElideMiddle



                                color:

                                    Appearance.colors.colOnSurface



                                font.pixelSize:

                                    Appearance.font.pixelSize.normal

                            }



                            StyledText {

                                Layout.fillWidth: true



                                text:

                                    videoDelegate.videoPath



                                elide: Text.ElideMiddle



                                color:

                                    Appearance.colors.colOnSurfaceVariant



                                font.pixelSize:

                                    Appearance.font.pixelSize.smaller

                            }

                        }



                        MaterialSymbol {

                            text: videoDelegate.selected

                                ? "check_circle"

                                : "chevron_right"



                            iconSize: 22



                            color: videoDelegate.selected

                                ? Appearance.colors.colPrimary

                                : Appearance.colors.colOnSurfaceVariant

                        }

                    }



                    HoverHandler {

                        id: hoverHandler

                    }



                    TapHandler {

                        onTapped: {

                            root.selectVideo(

                                videoDelegate.index

                            );

                        }

                    }

                }

            }



            StyledText {

                anchors.centerIn: parent



                visible:

                    folderModel.count === 0



                text: Translation.tr("No MP4 or WebM videos found.")



                color:

                    Appearance.colors.colOnSurfaceVariant



                font.pixelSize:

                    Appearance.font.pixelSize.small

            }

        }



        // Seleção e aplicação

        RowLayout {

            Layout.fillWidth: true

            spacing: 10



            ColumnLayout {

                Layout.fillWidth: true

                spacing: 3



                StyledText {

                    Layout.fillWidth: true



                    text: SettingsMessages.translate(root.selectedName.length > 0

                            ? root.selectedName

                            : "Nenhum vídeo selecionado", Translation.tr)



                    elide: Text.ElideMiddle



                    color:

                        Appearance.colors.colOnSurface



                    font.pixelSize:

                        Appearance.font.pixelSize.small

                }



                StyledText {

                    Layout.fillWidth: true



                    text: Translation.tr("Loop playback · No audio")



                    color:

                        Appearance.colors.colOnSurfaceVariant



                    font.pixelSize:

                        Appearance.font.pixelSize.smaller

                }

            }



            RippleButtonWithIcon {

                enabled:

                    root.selectedPath.length > 0



                materialIcon: "play_arrow"

                mainText: Translation.tr("Apply video")



                buttonRadius:

                    Appearance.rounding.small



                colBackground:

                    Appearance.colors.colPrimaryContainer



                colBackgroundHover:

                    Appearance.colors.colPrimaryContainerHover



                colRipple:

                    Appearance.colors.colPrimaryContainerActive



                onClicked: root.applyVideo()

            }

        }



        RowLayout {

            Layout.fillWidth: true

            spacing: 6



            visible:

                root.feedback.length > 0



            MaterialSymbol {

                text: root.hasError

                    ? "error"

                    : "info"



                iconSize: 18



                color: root.hasError

                    ? Appearance.colors.colError

                    : Appearance.colors.colOnSurfaceVariant

            }



            StyledText {

                Layout.fillWidth: true



                text: SettingsMessages.translate(root.feedback, Translation.tr)



                wrapMode: Text.WordWrap



                color: root.hasError

                    ? Appearance.colors.colError

                    : Appearance.colors.colOnSurfaceVariant



                font.pixelSize:

                    Appearance.font.pixelSize.small

            }

        }

    }

}
