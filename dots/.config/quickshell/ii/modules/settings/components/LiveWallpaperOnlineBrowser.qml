
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

    property string cachedPath: ""
    property bool checkingCache: false

    // Caminho registrado pela infraestrutura existente do Vesta Shell.
    readonly property string activeWallpaperPath:
        Config.options.background.wallpaperPath || ""

    readonly property bool selectedIsActive:
        selectedWallpaper !== null &&
        cachedPath.length > 0 &&
        normalizedPath(cachedPath) ===
            normalizedPath(activeWallpaperPath)

    property real downloadPercent: -1
    property real downloadReceived: 0
    property real downloadTotal: 0
    property real downloadSpeed: 0
    property string downloadStage: ""
    property var downloadResult: null
    property string downloadParseError: ""
    property bool cancelRequested: false

    readonly property bool downloading: downloadProc.running
    readonly property bool searching: searchProc.running

    readonly property bool busy:
        providerProc.running ||
        searchProc.running ||
        downloadProc.running

    readonly property bool canApply:
        !busy &&
        !checkingCache &&
        !selectedIsActive &&
        selectedWallpaper !== null &&
        providerSupportsDownload(selectedWallpaper.provider)

    function normalizedPath(path) {
        let value = String(path || "");

        if (value.startsWith("file://"))
            value = decodeURIComponent(value.substring(7));

        return value.replace(/\/+$/, "");
    }

    function providerIndex(code) {
        for (let i = 0; i < providers.length; i++) {
            if (providers[i].code === code)
                return i;
        }

        return -1;
    }

    function providerSupportsDownload(code) {
        const index = providerIndex(code);

        return index >= 0 &&
            providers[index].download === true;
    }

    function providerName(code) {
        const index = providerIndex(code);

        return index >= 0
            ? providers[index].name || code
            : code;
    }

    function formatBytes(bytes) {
        const value = Number(bytes);

        if (!isFinite(value) || value < 0)
            return "—";

        if (value < 1024)
            return Math.round(value) + " B";

        const units = ["KB", "MB", "GB", "TB"];
        let size = value / 1024;
        let index = 0;

        while (size >= 1024 && index < units.length - 1) {
            size /= 1024;
            index++;
        }

        return size.toFixed(size >= 100 ? 0 : 1) +
            " " + units[index];
    }

    function clearSelection() {
        selectedWallpaper = null;
        cachedPath = "";
        checkingCache = false;
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
            cachedPath = "";
            checkSelectedCache();
        }

        feedback = "";
        hasError = false;
    }

    function checkSelectedCache() {
        if (!selectedWallpaper || statusProc.running)
            return;

        checkingCache = true;
        cachedPath = "";

        statusProc.command = [
            "python3",
            scriptPath,
            "status",
            "--provider",
            selectedWallpaper.provider,
            "--image-id",
            selectedWallpaper.id
        ];

        statusProc.running = true;
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

    function resetDownloadState() {
        downloadPercent = -1;
        downloadReceived = 0;
        downloadTotal = 0;
        downloadSpeed = 0;
        downloadStage = "";
        downloadResult = null;
        downloadParseError = "";
        cancelRequested = false;
    }

    function applySelected() {
        if (!canApply)
            return;

        if (cachedPath.length > 0) {
            Wallpapers.apply(cachedPath);
            feedback = "Wallpaper local enviado para aplicação.";
            hasError = false;
            return;
        }

        const item = selectedWallpaper;

        resetDownloadState();

        downloadStage = "Preparando download...";

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
            item.id,
            "--events"
        ];

        downloadProc.running = true;
    }

    function cancelDownload() {
        if (!downloadProc.running || cancelRequested)
            return;

        cancelRequested = true;
        downloadStage = "Cancelando download...";
        feedback = "Interrompendo transferência...";

        downloadProc.running = false;
    }

    function handleDownloadLine(line) {
        const value = String(line).trim();

        if (!value.length)
            return;

        let data;

        try {
            data = JSON.parse(value);
        } catch (error) {
            downloadParseError = "Resposta de download inválida.";
            console.warn(
                "[LiveWallpaperOnlineBrowser] JSON:",
                value
            );
            return;
        }

        if (data.event === "progress") {
            downloadReceived = Number(data.received) || 0;
            downloadTotal = Number(data.total) || 0;
            downloadSpeed = Number(data.speed) || 0;

            downloadPercent = data.percent === null ||
                data.percent === undefined
                ? -1
                : Math.max(
                    0,
                    Math.min(100, Number(data.percent))
                );

            downloadStage = "Transferindo vídeo...";
            return;
        }

        if (data.event === "extracting") {
            downloadStage = "Extraindo vídeo...";
            downloadPercent = -1;
            return;
        }

        if (data.event === "cached") {
            downloadStage = "Arquivo encontrado no cache...";
            return;
        }

        if (data.ok !== undefined)
            downloadResult = data;
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

                if (root.providers.length > 0)
                    initialSearch.restart();
                else
                    root.feedback = "Nenhum provedor disponível.";

            } catch (error) {
                root.providersLoaded = false;
                root.hasError = true;

                root.feedback = "Erro nos provedores: " +
                    root.processError(
                        providerOutput.text,
                        providerErrors.text,
                        error.message
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
            }
        }
    }

    Process {
        id: statusProc
        running: false

        property string requestedId: ""
        property string requestedProvider: ""

        onStarted: {
            requestedId = root.selectedWallpaper
                ? root.selectedWallpaper.id : "";
            requestedProvider = root.selectedWallpaper
                ? root.selectedWallpaper.provider : "";
        }

        stdout: StdioCollector {
            id: statusOutput
        }

        stderr: StdioCollector {
            id: statusErrors
        }

        onExited: (exitCode, exitStatus) => {
            root.checkingCache = false;

            if (
                !root.selectedWallpaper ||
                root.selectedWallpaper.id !== requestedId ||
                root.selectedWallpaper.provider !== requestedProvider
            ) {
                if (root.selectedWallpaper)
                    cacheRetry.restart();
                return;
            }

            try {
                const data = JSON.parse(
                    statusOutput.text.trim()
                );

                if (exitCode !== 0 || data.ok !== true)
                    throw new Error(data.error || "Falha no cache.");

                root.cachedPath = data.cached === true
                    ? String(data.path || "")
                    : "";

            } catch (error) {
                root.cachedPath = "";
                console.warn(
                    "[LiveWallpaperOnlineBrowser] Cache:",
                    error.message,
                    statusErrors.text
                );
            }
        }
    }

    Timer {
        id: cacheRetry
        interval: 0
        repeat: false
        onTriggered: root.checkSelectedCache()
    }

    Process {
        id: downloadProc
        running: false

        stdout: SplitParser {
            onRead: line => root.handleDownloadLine(line)
        }

        stderr: StdioCollector {
            id: downloadErrors
        }

        onExited: (exitCode, exitStatus) => {
            if (root.cancelRequested) {
                root.downloadStage = "";
                root.feedback = "Download cancelado.";
                root.hasError = false;
                root.cancelRequested = false;
                return;
            }

            const data = root.downloadResult;

            if (
                exitCode === 0 &&
                data !== null &&
                data.ok === true &&
                data.path
            ) {
                root.cachedPath = String(data.path);
                root.downloadStage = "";
                root.hasError = false;

                Wallpapers.apply(root.cachedPath);

                root.feedback = data.cached === true
                    ? "Wallpaper do cache enviado para aplicação."
                    : "Wallpaper baixado e enviado para aplicação.";

                return;
            }

            root.hasError = true;
            root.downloadStage = "";

            root.feedback = "Erro no download: " +
                (
                    data && data.error
                        ? data.error
                        : root.downloadParseError.length > 0
                            ? root.downloadParseError
                            : downloadErrors.text.trim().length > 0
                                ? downloadErrors.text.trim()
                                : "O processo terminou sem concluir o download."
                );
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

                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 7

                        visible:
                            wallpaperDelegate.isSelected &&
                            root.cachedPath.length > 0

                        width: cachedLabel.implicitWidth + 16
                        height: 25
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colPrimaryContainer

                        StyledText {
                            id: cachedLabel
                            anchors.centerIn: parent

                            text: root.selectedIsActive
                                ? "Em uso"
                                : "Já baixado"

                            color: Appearance.colors.colOnPrimaryContainer

                            font.pixelSize:
                                Appearance.font.pixelSize.smaller
                        }
                    }

                    MaterialSymbol {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 8

                        visible: wallpaperDelegate.isSelected

                        text: root.selectedIsActive
                            ? "check_circle"
                            : "check_circle"

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

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            visible: root.downloading || root.cancelRequested

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: root.downloadStage === "Extraindo vídeo..."
                        ? "inventory_2"
                        : "downloading"

                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.downloadStage
                    color: Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                StyledText {
                    text: root.downloadPercent >= 0
                        ? root.downloadPercent.toFixed(1) + "%"
                        : "—"

                    color: Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 7

                radius: 4
                color: Appearance.colors.colLayer2
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom

                    width: parent.width *
                        Math.max(0, root.downloadPercent) / 100

                    radius: parent.radius
                    color: Appearance.colors.colPrimary

                    Behavior on width {
                        NumberAnimation {
                            duration: 120
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true

                    text:
                        root.formatBytes(root.downloadReceived) +
                        (
                            root.downloadTotal > 0
                                ? " / " +
                                    root.formatBytes(root.downloadTotal)
                                : " / tamanho desconhecido"
                        ) +
                        " · " +
                        root.formatBytes(root.downloadSpeed) +
                        "/s"

                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                RippleButtonWithIcon {
                    enabled:
                        root.downloading &&
                        !root.cancelRequested

                    materialIcon: "close"
                    mainText: root.cancelRequested
                        ? "Cancelando..."
                        : "Cancelar"

                    buttonRadius: Appearance.rounding.small

                    onClicked: root.cancelDownload()
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
                    : root.selectedIsActive
                        ? "check_circle"
                        : root.cachedPath.length > 0
                            ? "wallpaper"
                            : "download"

                mainText: root.downloading
                    ? "Baixando..."
                    : root.checkingCache
                        ? "Verificando..."
                        : root.selectedIsActive
                            ? "Em uso"
                            : root.cachedPath.length > 0
                                ? "Aplicar wallpaper"
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
