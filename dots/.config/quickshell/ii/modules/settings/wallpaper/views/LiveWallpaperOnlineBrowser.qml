import "../../utils/SettingsMessages.js" as SettingsMessages
import QtQuick

import QtQuick.Layouts

import Quickshell

import Quickshell.Io

import qs.modules.common

import qs.modules.common.widgets

import qs.services

import "../utils/WallpaperUtils.js" as WallpaperUtils

import "../utils/WallpaperPagination.js" as WallpaperPagination

import "../utils/WallpaperCommands.js" as WallpaperCommands

import "../utils/WallpaperResponses.js" as WallpaperResponses

import "../utils/WallpaperDownloadEvents.js" as WallpaperDownloadEvents

import "../utils/WallpaperDownloadState.js" as WallpaperDownloadState

import "../utils/WallpaperDownloadLifecycle.js" as WallpaperDownloadLifecycle

ContentSection {

    id: root

    title: Translation.tr("Explore live wallpapers online")

    icon: "travel_explore"

    Layout.fillWidth: true

    Layout.minimumWidth: 0

    readonly property string scriptPath: Quickshell.shellPath(

        "scripts/wallpaper/live/live_wallpaper.py"

    )

    property var providers: []

    property var results: []

    property var selectedWallpaper: null

    property string provider: "desktophut"

    property string resolution: ""
    readonly property var resolutions: [
        { name: Translation.tr("Any resolution"), code: "" },
        { name: "1920 × 1080+", code: "1920x1080" },
        { name: "2560 × 1440+", code: "2560x1440" },
        { name: "3840 × 2160+", code: "3840x2160" }
    ]


    property int page: 1

    property int lastSuccessfulPage: 1

    property int lastPage: 1

    property bool totalKnown: false

    property string feedback: ""

    property bool hasError: false

    property bool providersLoaded: false

    property var cachedPaths: ({})

    property string cachedPath: ""

    property bool checkingCache: false

    property bool cacheBatchPending: false


    readonly property bool selectedIsActive:
        Wallpapers.isActiveOnSelectedOutputs(cachedPath)

    property real downloadPercent: -1

    property real downloadReceived: 0

    property real downloadTotal: 0

    property real downloadSpeed: 0

    property string downloadStage: ""

    property var downloadTarget: null
    property string downloadLifecycle: WallpaperDownloadLifecycle.IDLE

    property var downloadResult: null

    property string downloadParseError: ""

    property bool cancelRequested: false

    readonly property bool downloading: downloadController.item !== null && downloadController.item.running

    readonly property bool searching: searchControllerLoader.item !== null && searchControllerLoader.item.running

    readonly property bool busy:

        (providerControllerLoader.item !== null && providerControllerLoader.item.running) ||

        searching ||

        downloading

    readonly property bool canApply:

        !busy &&

        !checkingCache &&

        !selectedIsActive && Wallpapers.selectedOutputAvailable && !Wallpapers.applying &&

        selectedWallpaper !== null &&

        providerSupportsDownload(selectedWallpaper.provider)

    function normalizedPath(path) {

        return WallpaperUtils.normalizedPath(path);

    }

    function cachedPathFor(item) {

        return WallpaperUtils.cachedPathFor(cachedPaths, item);

    }

    function isItemActive(item) {

        return Wallpapers.isActiveOnSelectedOutputs(cachedPathFor(item));

    }

    function updateCachedPath(id, path) {

        cachedPaths = WallpaperUtils.withCachedPath(cachedPaths, id, path);

        if (selectedWallpaper !== null && selectedWallpaper.id === id)

            cachedPath = String(path || "");

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

        return index >= 0 && providers[index].download === true;

    }

    function providerName(code) {

        const index = providerIndex(code);

        return index >= 0 ? providers[index].name || code : code;

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

            cachedPath = cachedPathFor(item);

            if (

                !cacheBatchPending &&

                !(cacheLoader.item !== null && cacheLoader.item.running) &&

                cachedPath.length === 0

            ) {

                checkSelectedCache();

            } else {

                checkingCache =

                    cacheBatchPending || (cacheLoader.item !== null && cacheLoader.item.running);

            }

        }

        feedback = "";

        hasError = false;

    }

    function checkSelectedCache() {

        if (!selectedWallpaper || statusProc.running)

            return;

        checkingCache = true;

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

    function refreshCacheBatch() {

        if ((cacheLoader.item !== null && cacheLoader.item.running)) {

            cacheBatchPending = true;

            return;

        }

        cacheBatchPending = false;

        if (results.length === 0) {

            cachedPaths = ({});

            checkingCache = false;

            return;

        }

        const ids = [];

        const seen = {};

        for (let i = 0; i < results.length; i++) {

            const id = String(results[i].id || "");

            if (!id || seen[id])

                continue;

            seen[id] = true;

            ids.push(id);

        }

        if (ids.length === 0) {

            cachedPaths = ({});

            checkingCache = false;

            return;

        }

        if (cacheLoader.item === null) {

            checkingCache = false;

            console.warn("[WallpaperCache] Controlador indisponível.");

            return;

        }

        cacheLoader.item.start(scriptPath, provider, ids);

    }

    function refreshProviders() {

        if (busy)

            return;

        feedback = "Carregando provedores...";

        hasError = false;

        providersLoaded = false;

        if (providerControllerLoader.item === null) {

            providersLoaded = false;

            hasError = true;

            feedback = "Controlador de provedores indisponível.";

            return;

        }

        providerControllerLoader.item.start(

            WallpaperCommands.providers(scriptPath, "", true)

        );

    }

    function clearSearch() {

        if (root.busy || !root.providersLoaded ||

            searchField.text.length === 0)

            return;

        searchField.text = "";

        root.search(true);

    }

    function search(resetPage) {

        if (busy || !providersLoaded)

            return;

        if (resetPage)

            page = 1;

        feedback = "Pesquisando wallpapers animados...";

        hasError = false;

        if (searchControllerLoader.item === null) {

            hasError = true;

            feedback = "Controlador de pesquisa indisponível.";

            return;

        }

        searchControllerLoader.item.start(

            WallpaperCommands.searchLive(

                scriptPath, provider, searchField.text.trim(), page, resolution

            ),

            page

        );

    }

    // O backend atual só confirma a existência

    // da próxima página. Não inventamos um total.

    function visiblePageNumbers() {

        return WallpaperPagination.visiblePages(page, lastPage, totalKnown);

    }

    function changePage(targetPage) {

        if (

            busy ||

            targetPage < 1 ||

            targetPage > lastPage ||

            targetPage === page

        ) {

            return;

        }

        page = targetPage;

        search(false);

    }

    function resetDownloadState() {

        const progress = WallpaperDownloadState.reset();

        downloadPercent = progress.percent;

        downloadReceived = progress.received;

        downloadTotal = progress.total;

        downloadSpeed = progress.speed;

        downloadStage = "";

        downloadResult = null;

        downloadParseError = "";

        cancelRequested = false;

    }

    function applySelected() {

        if (!canApply)

            return;

        if (cachedPath.length > 0) {

            if (!Wallpapers.applyToSelected(cachedPath)) return;

            feedback = "Wallpaper local enviado para aplicação.";

            hasError = false;

            return;

        }

        const item = selectedWallpaper;
        downloadTarget = Wallpapers.captureTarget();

        resetDownloadState();

        downloadLifecycle = WallpaperDownloadLifecycle.start();

        downloadStage = "Preparando download...";

        feedback = "Baixando " +

            (item.title || "wallpaper") +

            " de " +

            providerName(item.provider) +

            "...";

        hasError = false;

        if (downloadController.item === null) {

            downloadStage = "";

            hasError = true;

            feedback = "Controlador de download indisponível.";

            return;

        }

        downloadController.item.start([

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

        ], item.id);

    }

    function cancelDownload() {

        if (!downloading || cancelRequested)

            return;

        cancelRequested = true;

        downloadLifecycle = WallpaperDownloadLifecycle.cancel(downloadLifecycle);

        downloadStage = "Cancelando download...";

        feedback = "Interrompendo transferência...";

        downloadController.item.cancel();

    }

    function handleDownloadLine(line) {

        const parsed = WallpaperDownloadEvents.parseLine(line);

        if (parsed.empty)

            return;

        if (!parsed.valid) {

            downloadParseError =

                "Resposta de download inválida.";

            console.warn(

                "[LiveWallpaperOnlineBrowser] JSON:",

                parsed.raw

            );

            return;

        }

        const data = parsed.data;

        downloadLifecycle = WallpaperDownloadLifecycle.event(downloadLifecycle, data);

        if (data.event === "progress") {

            const progress = WallpaperDownloadState.liveProgress(data);

            downloadReceived = progress.received;

            downloadTotal = progress.total;

            downloadSpeed = progress.speed;

            downloadPercent = progress.percent;

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

        return WallpaperCommands.processError(output, errors, fallback);

    }

    Loader {

        id: providerControllerLoader

        active: true

        source: "../controllers/WallpaperProviderController.qml"

        onLoaded: {

            item.completed.connect(root.handleProvidersCompleted);

            item.failed.connect(root.handleProvidersFailed);

        }

    }

    function handleProvidersCompleted(availableProviders) {

        root.providers = availableProviders;

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

    }

    function handleProvidersFailed(message, details) {

        root.providersLoaded = false;

        root.hasError = true;

        root.feedback = "Erro nos provedores: " + message;

        if (details.length > 0)

            console.warn("[LiveWallpaperOnlineBrowser] Providers:", details);

    }

    Timer {

        id: initialSearch

        interval: 0

        repeat: false

        onTriggered: root.search(true)

    }

    Loader {

        id: searchControllerLoader

        active: true

        source: "../controllers/LiveWallpaperSearchController.qml"

        onLoaded: {

            item.completed.connect(root.handleSearchCompleted);

            item.failed.connect(root.handleSearchFailed);

        }

    }

    function handleSearchCompleted(items, resultPage, resultLastPage) {

        root.clearSelection();

        root.cachedPaths = ({});

        root.results = items;

        root.page = resultPage;

        root.lastSuccessfulPage = resultPage;

        root.lastPage = resultLastPage;

        // O backend informa apenas se existe a próxima página.

        root.totalKnown = root.lastPage <= root.page;

        root.hasError = false;

        root.feedback = root.results.length > 0 ? "" : "Nenhum wallpaper encontrado.";

        grid.positionViewAtBeginning();

        root.refreshCacheBatch();

    }

    function handleSearchFailed(message, details) {

        root.page = root.lastSuccessfulPage;

        root.hasError = true;

        root.feedback = "Erro na pesquisa: " + message;

        if (details.length > 0)

            console.warn("[LiveWallpaperOnlineBrowser] Search:", details);

    }

    Loader {

        id: cacheLoader

        active: true

        source: "../controllers/WallpaperCacheController.qml"

        onLoaded: {

            item.completed.connect(root.cacheCompleted);

            item.failed.connect(root.cacheFailed);

        }

    }

    function cacheIsStale(requestedProvider, requestedIds) {

        const ids = results.map(item => String(item.id || ""))

            .filter(id => id.length > 0)

            .filter((id, i, arr) => arr.indexOf(id) === i).join(",");

        return cacheBatchPending ||

            requestedProvider !== provider || requestedIds !== ids;

    }

    function cacheCompleted(paths, requestedProvider, requestedIds) {

        if (cacheIsStale(requestedProvider, requestedIds)) {

            refreshCacheBatch();

            return;

        }

        cachedPaths = paths;

        if (selectedWallpaper !== null)

            cachedPath = cachedPathFor(selectedWallpaper);

        checkingCache = false;

    }

    function cacheFailed(message, details, requestedProvider, requestedIds) {

        if (cacheIsStale(requestedProvider, requestedIds)) {

            refreshCacheBatch();

            return;

        }

        checkingCache = false;

        console.warn("[WallpaperCache]", message, details);

    }

    Process {

        id: statusProc

        running: false

        property string requestedId: ""

        property string requestedProvider: ""

        onStarted: {

            requestedId = root.selectedWallpaper

                ? root.selectedWallpaper.id

                : "";

            requestedProvider = root.selectedWallpaper

                ? root.selectedWallpaper.provider

                : "";

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

                if (exitCode !== 0 || data.ok !== true) {

                    throw new Error(

                        data.error || "Falha no cache."

                    );

                }

                const path = data.cached === true

                    ? String(data.path || "")

                    : "";

                root.updateCachedPath(requestedId, path);

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

    Loader {

        id: downloadController

        active: true

        source: "../controllers/WallpaperDownloadController.qml"

        onLoaded: {

            item.lineReceived.connect(root.handleDownloadLine);

            item.finished.connect(root.handleDownloadExited);

        }

    }

    function downloadFailureMessage(message) {
       const raw = String(message || "").trim();
       // A saída técnica permanece no console, nunca na interface.
       if (/\b(?:HTTP\s*(?:Error\s*)?)?403\b|Forbidden/i.test(raw))
           return "O servidor recusou o download (HTTP 403). Este wallpaper pode estar protegido.";
       if (/\b(?:HTTP\s*(?:Error\s*)?)?404\b|Not Found/i.test(raw))
           return "O arquivo não foi encontrado no servidor (HTTP 404).";
       if (/\b(?:HTTP\s*(?:Error\s*)?)?410\b|Gone/i.test(raw))
           return "Este wallpaper não está mais disponível (HTTP 410).";
       if (/\b(?:HTTP\s*(?:Error\s*)?)?429\b|Too Many Requests/i.test(raw))
           return "O servidor limitou os downloads (HTTP 429). Aguarde e tente novamente.";
       if (/\b(?:HTTP\s*(?:Error\s*)?)?5\d\d\b|Internal Server Error/i.test(raw))
           return "O servidor está com problemas temporários. Tente novamente mais tarde.";
       if (/timed?\s*out|TimeoutError|tempo\s*esgotado/i.test(raw))
           return "A conexão demorou demais. Verifique a rede e tente novamente.";
       if (/SSL|CERTIFICATE_VERIFY_FAILED|certificate verify failed/i.test(raw))
           return "Não foi possível validar a conexão segura com o servidor.";
       if (/Name or service not known|Temporary failure in name resolution|gaierror/i.test(raw))
           return "Não foi possível localizar o servidor. Verifique a conexão com a internet.";
       if (/cancel/i.test(raw))
           return "Download cancelado.";
       if (/URL fora dos domínios permitidos/i.test(raw))
           return "O endereço de download foi rejeitado por segurança.";
       if (/O servidor não retornou vídeo|Content-Type/i.test(raw))
           return "O servidor não forneceu um arquivo de vídeo válido.";
       if (/download incompleto|arquivo baixado está vazio/i.test(raw))
           return "O download não foi concluído corretamente. Tente novamente.";
       return "Não foi possível baixar este wallpaper. Consulte os logs para detalhes.";
   }

   function handleDownloadExited(exitCode, details) {

        const outcome = WallpaperDownloadLifecycle.terminal(

            root.downloadLifecycle,

            exitCode,

            root.downloadResult !== null &&

                root.downloadResult.ok === true &&

                Boolean(root.downloadResult.path),

            true

        );

        root.downloadLifecycle = outcome.state;

        const actions = WallpaperDownloadLifecycle.finishActions(outcome);

        if (actions.clearCancellation) {

            root.downloadStage = "";

            root.feedback = "Download cancelado.";

            root.hasError = false;

            root.cancelRequested = false;

            return;

        }

        const data = root.downloadResult;

        if (actions.applyResult) {

            const path = String(data.path);

            if (root.selectedWallpaper !== null) {

                root.updateCachedPath(

                    root.selectedWallpaper.id,

                    path

                );

            }

            root.downloadStage = "";

            root.hasError = false;

            if (!Wallpapers.applyToSelected(path, downloadTarget)) {
                root.hasError = true;
                root.feedback = "Wallpaper application failed";
                return;
            }

            root.feedback = data.cached === true

                ? "Wallpaper do cache enviado para aplicação."

                : "Wallpaper baixado e enviado para aplicação.";

            return;

        }

        root.hasError = true;

        root.downloadStage = "";

        const errorText = data && data.error

            ? String(data.error)

            : details.length > 0

                ? details

                : root.downloadParseError;

        root.feedback = root.downloadFailureMessage(errorText);

        if (errorText.length > 0)

            console.warn("[LiveWallpaperOnlineBrowser] Download:", errorText);

        // Registra stderr para diagnóstico sem exibi-lo na galeria.
        const technicalDetails = String(details || "").trim();
        if (technicalDetails.length > 0)
            console.warn("[LiveWallpaperOnlineBrowser] stderr do download:\n" + technicalDetails);

    }

    ColumnLayout {

        Layout.fillWidth: true

        Layout.minimumWidth: 0

        spacing: 12

        StyledText {

            Layout.fillWidth: true

            wrapMode: Text.WordWrap

            text: Translation.tr("Browse live wallpapers on DesktopHut, MotionBGS and MoeWalls. Select a video to download and use as your wallpaper.")

            color: Appearance.colors.colOnSurfaceVariant

            font.pixelSize: Appearance.font.pixelSize.small

        }

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 8

            MaterialSymbol {
                text: "aspect_ratio"
                iconSize: 20
                color: Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                text: Translation.tr("Resolution")
                color: Appearance.colors.colOnSurface
                font.pixelSize: Appearance.font.pixelSize.small
            }

            StyledComboBox {
                Layout.preferredWidth: 230
                Layout.minimumWidth: 150
                enabled: !root.busy && root.providersLoaded
                buttonIcon: "aspect_ratio"
                textRole: "name"
                model: root.resolutions
                currentIndex: {
                    for (let i = 0; i < root.resolutions.length; i++) {
                        if (root.resolutions[i].code === root.resolution)
                            return i;
                    }
                    return 0;
                }
                onActivated: index => {
                    if (index < 0 || index >= root.resolutions.length)
                        return;
                    const next = root.resolutions[index].code;
                    if (next === root.resolution)
                        return;
                    root.resolution = next;
                    root.search(true);
                }
            }

            Item { Layout.fillWidth: true }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.resolution !== ""
            text: Translation.tr("The filter uses the original resolution advertised by the provider. Videos without resolution information are excluded from the filter.")
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        RowLayout {

            Layout.fillWidth: true

            Layout.minimumWidth: 0

            spacing: 8

            StyledComboBox {

                Layout.preferredWidth: 170

                Layout.minimumWidth: 110

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

                Layout.minimumWidth: 90

                Layout.preferredHeight: 48

                enabled: !root.busy

                placeholderText: Translation.tr("Search live wallpapers...")

                onAccepted: root.search(true)

            }

            Loader {

                Layout.preferredHeight: 48

                Layout.preferredWidth: item ? item.implicitWidth : 0

                source: "../components/WallpaperSearchActions.qml"

                onLoaded: {

                    item.canSearch = Qt.binding(() => !root.busy && root.providersLoaded);

                    item.hasQuery = Qt.binding(() => searchField.text.length > 0);

                    item.searchRequested.connect(() => root.search(true));

                    item.clearRequested.connect(() => root.clearSearch());

                }

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

                text: SettingsMessages.translate(root.results.length +

                    (root.results.length === 1

                        ? " wallpaper"

                        : " wallpapers"), Translation.tr)

                color: Appearance.colors.colOnSurfaceVariant

                font.pixelSize: Appearance.font.pixelSize.small

            }

        }

        RowLayout {

            Layout.fillWidth: true

            spacing: 6

            Layout.minimumHeight: 24

            Layout.preferredHeight: 24

            Layout.maximumHeight: 24

            visible: true

            opacity: (root.feedback.length > 0 || root.busy) ? 1 : 0

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

                text: SettingsMessages.translate(root.feedback.length > 0

                    ? root.feedback

                    : root.busy

                        ? "Processando..."

                        : "", Translation.tr)

                wrapMode: Text.WordWrap

                maximumLineCount: 2
                elide: Text.ElideRight
                color: root.hasError

                    ? Appearance.colors.colError

                    : Appearance.colors.colOnSurfaceVariant

                font.pixelSize: Appearance.font.pixelSize.small

            }

        }

        GridView {

            id: grid

            Layout.fillWidth: true

            Layout.minimumWidth: 0

            // Três linhas completas: 3 * cellHeight.

            Layout.preferredHeight: cellHeight * 3

            clip: true

            readonly property int columns:

                Math.max(1, Math.floor(width / 170))

            cellWidth: width / columns

            cellHeight: 130

            model: root.results

            boundsBehavior: Flickable.StopAtBounds

            delegate: Loader {

                id: cardLoader

                required property var modelData

                width: grid.cellWidth

                height: grid.cellHeight

                // Carregamento local explícito, compatível com o scanner QML.

                Component.onCompleted: setSource("../components/WallpaperCard.qml", {

                    "wallpaper": modelData,

                    "live": true

                })

                onLoaded: {

                    item.wallpaper = Qt.binding(() => cardLoader.modelData);

                    item.selected = Qt.binding(() => root.selectedWallpaper !== null && root.selectedWallpaper.id === cardLoader.modelData.id);

                    item.cached = Qt.binding(() => root.cachedPathFor(cardLoader.modelData).length > 0);

                    item.active = Qt.binding(() => root.isItemActive(cardLoader.modelData));

                    item.busy = Qt.binding(() => root.busy);

                    item.activated.connect(() => root.selectWallpaper(cardLoader.modelData));

                }

            }

        }

        // Progresso abaixo da grade, como nos wallpapers estáticos.

        ColumnLayout {

            Layout.fillWidth: true

            spacing: 8

            visible:

                root.downloading ||

                root.cancelRequested

            RowLayout {

                Layout.fillWidth: true

                spacing: 8

                MaterialSymbol {

                    text: (root.downloadStage === "Extraindo vídeo..."

                        ? "inventory_2"

                        : "downloading")

                    iconSize: 20

                    color: Appearance.colors.colPrimary

                }

                StyledText {

                    Layout.fillWidth: true

                    text: SettingsMessages.translate(root.downloadStage, Translation.tr)

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

                    text: SettingsMessages.translate(root.formatBytes(root.downloadReceived) +

                        (

                            root.downloadTotal > 0

                                ? " / " +

                                    root.formatBytes(root.downloadTotal)

                                : " / tamanho desconhecido"

                        ) +

                        " · " +

                        root.formatBytes(root.downloadSpeed) +

                        "/s", Translation.tr)

                    color: Appearance.colors.colOnSurfaceVariant

                    font.pixelSize: Appearance.font.pixelSize.small

                }

                RippleButtonWithIcon {

                    enabled:

                        root.downloading &&

                        !root.cancelRequested

                    materialIcon: "close"

                    mainText: SettingsMessages.translate(root.cancelRequested

                        ? "Cancelando..."

                        : "Cancelar", Translation.tr)

                    buttonRadius: Appearance.rounding.small

                    onClicked: root.cancelDownload()

                }

            }

        }

        // Paginação compacta: Anterior | páginas | Próxima.

        // A ação de download fica em uma linha independente.

        ColumnLayout {

            Layout.fillWidth: true

            Layout.minimumWidth: 0

            spacing: 6

            RowLayout {

                Layout.fillWidth: true

                Layout.minimumWidth: 0

                spacing: 6

                RippleButtonWithIcon {

                    enabled: !root.busy && root.page > 1

                    materialIcon: "chevron_left"

                    mainText: Translation.tr("Previous")

                    buttonRadius: Appearance.rounding.small

                    onClicked: root.changePage(root.page - 1)

                }

                Flow {

                    Layout.fillWidth: true

                    Layout.minimumWidth: 0

                    Layout.preferredHeight: childrenRect.height

                    spacing: 4

                    Repeater {

                        model: root.visiblePageNumbers()

                        delegate: Rectangle {

                            id: pageButton

                            required property int modelData

                            readonly property bool current: modelData === root.page

                            readonly property bool clickable:

                                !root.busy && modelData > 0 && !current

                            width: modelData < 0

                                ? 24

                                : Math.max(34, pageNumberText.implicitWidth + 16)

                            height: 32

                            radius: Appearance.rounding.small

                            color: current

                                ? Appearance.colors.colPrimaryContainer

                                : pageHover.hovered && clickable

                                    ? Appearance.colors.colLayer2

                                    : "transparent"

                            Behavior on color {

                                ColorAnimation { duration: 140 }

                            }

                            StyledText {

                                id: pageNumberText

                                anchors.centerIn: parent

                                text: pageButton.modelData < 0

                                    ? "…"

                                    : String(pageButton.modelData)

                                color: pageButton.current

                                    ? Appearance.colors.colOnPrimaryContainer

                                    : Appearance.colors.colOnSurface

                                font.pixelSize: Appearance.font.pixelSize.small

                            }

                            HoverHandler {

                                id: pageHover

                                enabled: pageButton.clickable

                                cursorShape: Qt.PointingHandCursor

                            }

                            TapHandler {

                                enabled: pageButton.clickable

                                onTapped: root.changePage(pageButton.modelData)

                            }

                        }

                    }

                }

                RippleButtonWithIcon {

                    enabled: !root.busy && root.page < root.lastPage

                    materialIcon: "chevron_right"

                    mainText: Translation.tr("Next")

                    buttonRadius: Appearance.rounding.small

                    onClicked: root.changePage(root.page + 1)

                }

            }

            RowLayout {

                Layout.fillWidth: true

                Layout.minimumWidth: 0

                Item { Layout.fillWidth: true }

            RippleButtonWithIcon {

                enabled: root.canApply

                materialIcon: root.downloading

                    ? "progress_activity"

                    : root.selectedIsActive

                        ? "check_circle"

                        : root.cachedPath.length > 0

                            ? "wallpaper"

                            : "download"

                mainText: SettingsMessages.translate(root.downloading

                    ? "Baixando..."

                    : root.checkingCache

                        ? "Verificando..."

                        : root.selectedIsActive

                            ? "Em uso"

                            : root.cachedPath.length > 0

                                ? "Aplicar wallpaper"

                                : "Baixar e aplicar", Translation.tr)

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

        }

    }

    Component.onCompleted: root.refreshProviders()

}
