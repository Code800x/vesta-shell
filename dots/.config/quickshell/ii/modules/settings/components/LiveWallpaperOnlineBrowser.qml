
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentSection {
    id: root

    title: "Explorar Live Wallpapers Online"
    icon: "travel_explore"
    Layout.fillWidth: true

    readonly property string scriptPath: Quickshell.shellPath(
        "scripts/wallpaper/live/live_wallpaper.py"
    )

    property var providers: []
    property var results: []
    property var selectedWallpaper: null

    property string provider: "desktophut"
    property int page: 1
    property int lastPage: 1

    property string feedback: ""
    property bool hasError: false
    property bool providersLoaded: false

    readonly property bool busy:
        providerProc.running ||
        searchProc.running ||
        downloadProc.running

    readonly property bool downloading: downloadProc.running
    readonly property bool searching: searchProc.running

    readonly property bool canApply:
        !busy &&
        selectedWallpaper !== null &&
        providerSupportsDownload(
            selectedWallpaper.provider
        )

    function providerIndex(code) {
        for (let i = 0; i < providers.length; i++) {
            if (providers[i].code === code)
                return i;
        }

        return -1;
    }

    function providerSupportsDownload(code) {
        const index = providerIndex(code);

        if (index < 0)
            return false;

        return providers[index].download === true;
    }

    function providerName(code) {
        const index = providerIndex(code);

        if (index < 0)
            return code;

        return providers[index].name || code;
    }

    function clearSelection() {
        selectedWallpaper = null;
    }

    function selectWallpaper(item) {
        if (busy || !item)
            return;

        if (
            selectedWallpaper !== null &&
            selectedWallpaper.id === item.id
        ) {
            clearSelection();
        } else {
            selectedWallpaper = item;
        }

        feedback = "";
        hasError = false;
    }

    function refreshProviders() {
        if (busy)
            return;

        feedback = "Carregando provedores...";
        hasError = false;
        providersLoaded = false;

        providerProc.command = [
            "python3",
            scriptPath,
            "providers"
        ];

        providerProc.running = true;
    }

    function search(resetPage) {
        if (busy || !providersLoaded)
            return;

        if (resetPage) {
            page = 1;
            lastPage = 1;
        }

        clearSelection();

        feedback = "Pesquisando wallpapers animados...";
        hasError = false;

        searchProc.command = [
            "python3",
            scriptPath,
            "search",
            "--provider",
            provider,
            "--query",
            searchField.text.trim(),
            "--page",
            String(page)
        ];

        searchProc.running = true;
    }

    function changePage(targetPage) {
        if (
            busy ||
            targetPage < 1 ||
            targetPage > lastPage
        ) {
            return;
        }

        page = targetPage;
        search(false);
    }

    function applySelected() {
        if (!canApply)
            return;

        const item = selectedWallpaper;

        feedback = "Baixando " +
            (item.title || "wallpaper") +
            " de " +
            providerName(item.provider) +
            "...";

        hasError = false;

        downloadProc.command = [
            "python3",
            scriptPath,
            "download",
            "--provider",
            item.provider,
            "--url",
            item.url,
            "--image-id",
            item.id
        ];

        downloadProc.running = true;
    }

    function processError(output, errors, fallback) {
        let message = fallback;

        try {
            const data = JSON.parse(output.trim());

            if (data.error)
                message = data.error;
        } catch (error) {
            const stderrText = errors.trim();

            if (stderrText.length > 0) {
                const lines = stderrText.split("\n");

                message = lines[lines.length - 1] || fallback;
            }
        }

        return message;
    }

    Process {
        id: providerProc
        running: false

        stdout: StdioCollector {
            id: providerOutput
        }

        stderr: StdioCollector {
            id: providerErrors
        }

        onExited: (exitCode, exitStatus) => {
            try {
                const data = JSON.parse(
                    providerOutput.text.trim()
                );

                if (exitCode !== 0 || data.ok !== true) {
                    throw new Error(
                        data.error || "Falha ao carregar provedores."
                    );
                }

                root.providers = data.providers || [];
                root.providersLoaded = true;

                if (
                    root.providerIndex(root.provider) < 0 &&
                    root.providers.length > 0
                ) {
                    root.provider = root.providers[0].code;
                }

                root.feedback = "";
                root.hasError = false;

                if (root.providers.length > 0) {
                    initialSearch.restart();
                } else {
                    root.feedback = "Nenhum provedor disponível.";
                }
            } catch (error) {
                root.providersLoaded = false;
                root.hasError = true;

                root.feedback = "Erro nos provedores: " +
                    root.processError(
                        providerOutput.text,
                        providerErrors.text,
                        error.message
                    );

                console.warn(
                    "[LiveWallpaperOnlineBrowser] Providers:",
                    providerErrors.text
                );
            }
        }
    }

    Timer {
        id: initialSearch
        interval: 0
        repeat: false

        onTriggered: root.search(true)
    }

    Process {
        id: searchProc
        running: false

        stdout: StdioCollector {
            id: searchOutput
        }

        stderr: StdioCollector {
            id: searchErrors
        }

        onExited: (exitCode, exitStatus) => {
            try {
                const data = JSON.parse(
                    searchOutput.text.trim()
                );

                if (exitCode !== 0 || data.ok !== true) {
                    throw new Error(
                        data.error || "Falha na pesquisa."
                    );
                }

                root.results = data.items || [];

                root.page = Math.max(
                    1,
                    Number(data.page) || root.page
                );

                root.lastPage = Math.max(
                    root.page,
                    Number(data.last_page) || root.page
                );

                root.hasError = false;

                root.feedback = root.results.length > 0
                    ? ""
                    : "Nenhum wallpaper encontrado.";

                grid.positionViewAtBeginning();
            } catch (error) {
                root.results = [];
                root.lastPage = root.page;
                root.hasError = true;

                root.feedback = "Erro na pesquisa: " +
                    root.processError(
                        searchOutput.text,
                        searchErrors.text,
                        error.message
                    );

                console.warn(
                    "[LiveWallpaperOnlineBrowser] Search:",
                    searchErrors.text
                );
            }
        }
    }

    Process {
        id: downloadProc
        running: false

        stdout: StdioCollector {
            id: downloadOutput
        }

        stderr: StdioCollector {
            id: downloadErrors
        }

        onExited: (exitCode, exitStatus) => {
            try {
                const data = JSON.parse(
                    downloadOutput.text.trim()
                );

                if (
                    exitCode !== 0 ||
                    data.ok !== true ||
                    !data.path
                ) {
                    throw new Error(
                        data.error || "Falha no download."
                    );
                }

                Wallpapers.apply(data.path);

                root.hasError = false;
                root.feedback =
                    "Wallpaper baixado e enviado para aplicação.";
            } catch (error) {
                root.hasError = true;

                root.feedback = "Erro no download: " +
                    root.processError(
                        downloadOutput.text,
                        downloadErrors.text,
                        error.message
                    );

                console.warn(
                    "[LiveWallpaperOnlineBrowser] Download:",
                    downloadErrors.text
                );
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap

            text:
                "Explore wallpapers animados no DesktopHut, " +
                "MotionBGS e MoeWalls. Selecione um vídeo " +
                "para baixar e aplicar como plano de fundo."

            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledComboBox {
                Layout.preferredWidth: 170

                enabled:
                    !root.busy &&
                    root.providersLoaded

                buttonIcon: "public"
                textRole: "name"
                model: root.providers

                currentIndex:
                    root.providerIndex(root.provider)

                onActivated: index => {
                    if (
                        index < 0 ||
                        index >= root.providers.length
                    ) {
                        return;
                    }

                    const nextProvider =
                        root.providers[index].code;

                    if (nextProvider === root.provider)
                        return;

                    root.provider = nextProvider;
                    root.search(true);
                }
            }

            MaterialTextField {
                id: searchField

                Layout.fillWidth: true
                Layout.preferredHeight: 48

                enabled: !root.busy

                placeholderText:
                    "Pesquisar wallpapers animados..."

                onAccepted: root.search(true)
            }

            RippleButtonWithIcon {
                Layout.preferredHeight: 48

                enabled:
                    !root.busy &&
                    root.providersLoaded

                materialIcon: "search"
                mainText: "Pesquisar"

                buttonRadius: Appearance.rounding.small

                onClicked: root.search(true)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true

                text: root.providerName(root.provider)

                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            StyledText {
                text:
                    root.results.length +
                    (root.results.length === 1
                        ? " wallpaper"
                        : " wallpapers")

                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            visible:
                root.feedback.length > 0 ||
                root.busy

            MaterialSymbol {
                text: root.hasError
                    ? "error"
                    : root.busy
                        ? "progress_activity"
                        : "info"

                iconSize: 18

                color: root.hasError
                    ? Appearance.colors.colError
                    : Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true

                text: root.feedback.length > 0
                    ? root.feedback
                    : root.busy
                        ? "Processando..."
                        : ""

                wrapMode: Text.WordWrap

                color: root.hasError
                    ? Appearance.colors.colError
                    : Appearance.colors.colOnSurfaceVariant

                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        GridView {
            id: grid

            Layout.fillWidth: true
            Layout.preferredHeight: 420

            clip: true

            readonly property int columns:
                Math.max(1, Math.floor(width / 170))

            cellWidth: width / columns
            cellHeight: 130

            model: root.results

            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: wallpaperDelegate

                required property var modelData

                readonly property bool isSelected:
                    root.selectedWallpaper !== null &&
                    root.selectedWallpaper.id === modelData.id

                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    id: card

                    anchors.fill: parent
                    anchors.margins: 4

                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    clip: true

                    Image {
                        id: thumbnail

                        anchors.fill: parent

                        source:
                            wallpaperDelegate.modelData.thumb || ""

                        fillMode: Image.PreserveAspectCrop

                        asynchronous: true
                        cache: true

                        sourceSize.width: 340
                        sourceSize.height: 240
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent

                        visible:
                            thumbnail.status !== Image.Ready

                        text: "movie"
                        iconSize: 28

                        color: Appearance.colors.colOnSurface
                    }

                    Rectangle {
                        anchors.fill: parent

                        color: Appearance.colors.colPrimary

                        opacity:
                            wallpaperDelegate.isSelected
                                ? 0.18
                                : hoverHandler.hovered
                                    ? 0.12
                                    : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 140
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent

                        radius: card.radius
                        color: "transparent"

                        border.width:
                            wallpaperDelegate.isSelected ? 3 : 0

                        border.color:
                            Appearance.colors.colPrimary
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom

                        height: 34
                        color: "#AA000000"

                        StyledText {
                            anchors.fill: parent
                            anchors.margins: 7

                            text:
                                wallpaperDelegate.modelData.title || ""

                            color: "white"

                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter

                            font.pixelSize:
                                Appearance.font.pixelSize.smaller
                        }
                    }

                    MaterialSymbol {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8

                        visible: wallpaperDelegate.isSelected

                        text: "check_circle"
                        iconSize: 25

                        color: Appearance.colors.colPrimary
                    }

                    HoverHandler {
                        id: hoverHandler
                    }

                    TapHandler {
                        enabled: !root.busy

                        onTapped: root.selectWallpaper(
                            wallpaperDelegate.modelData
                        )
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            RippleButtonWithIcon {
                enabled:
                    !root.busy &&
                    root.page > 1

                materialIcon: "chevron_left"
                mainText: "Anterior"

                buttonRadius: Appearance.rounding.small

                onClicked:
                    root.changePage(root.page - 1)
            }

            StyledText {
                text: root.page + " / " + root.lastPage

                color: Appearance.colors.colOnSurface
                font.pixelSize: Appearance.font.pixelSize.small
            }

            RippleButtonWithIcon {
                enabled:
                    !root.busy &&
                    root.page < root.lastPage

                materialIcon: "chevron_right"
                mainText: "Próxima"

                buttonRadius: Appearance.rounding.small

                onClicked:
                    root.changePage(root.page + 1)
            }

            Item {
                Layout.fillWidth: true
            }

            RippleButtonWithIcon {
                enabled: root.canApply

                materialIcon: root.downloading
                    ? "progress_activity"
                    : "wallpaper"

                mainText: root.downloading
                    ? "Baixando..."
                    : "Baixar e aplicar"

                buttonRadius: Appearance.rounding.small

                colBackground:
                    Appearance.colors.colPrimaryContainer

                colBackgroundHover:
                    Appearance.colors.colPrimaryContainerHover

                colRipple:
                    Appearance.colors.colPrimaryContainerActive

                onClicked: root.applySelected()
            }
        }

        StyledText {
            Layout.fillWidth: true

            visible:
                root.selectedWallpaper !== null &&
                !root.downloading

            text: root.selectedWallpaper
                ? "Selecionado: " +
                    root.selectedWallpaper.title
                : ""

            wrapMode: Text.WordWrap

            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    Component.onCompleted: root.refreshProviders()
}
