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
    title: Translation.tr("Explore wallpapers online")
    icon: "travel_explore"
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    readonly property string scriptPath: Quickshell.shellPath(
        "scripts/wallpaper/wallpaper.py"
    )
    property var results: []
    property int page: 1
    property int lastSuccessfulPage: 1
    property int lastPage: 1
    property string provider: "wallhaven"
    property string category: "111"
    property string sorting: "date_added"
    property string resolution: ""
    property string purity: "100"
    property var availableProviders: []
    property bool providersLoaded: false
    property string feedback: ""
    property bool hasError: false
    property var selectedWallpaper: null
    property string selectedId: ""
    property var cachedPaths: ({})
    property bool cacheBatchPending: false
    property bool checkingCache: false
    property bool downloadCancelling: false
    property bool downloadCompleted: false
    property string downloadLifecycle: WallpaperDownloadLifecycle.IDLE
    property int downloadPercentage: -1
    property double downloadedBytes: 0
    property double downloadTotalBytes: 0
    readonly property string activeWallpaperPath:
        Config.options.background.wallpaperPath || ""
    readonly property string selectedCachedPath:
        selectedId.length > 0
            ? String(cachedPaths[selectedId] || "")
            : ""
    readonly property bool selectedIsActive:
        selectedCachedPath.length > 0 &&
        normalizedPath(selectedCachedPath) ===
            normalizedPath(activeWallpaperPath)
    readonly property bool busy:
        (providerControllerLoader.item !== null && providerControllerLoader.item.running) ||
        (searchControllerLoader.item !== null && searchControllerLoader.item.running) ||
        (downloadController.item !== null && downloadController.item.running) ||
        downloadCancelling
    readonly property bool canApply:
        !busy &&
        !checkingCache &&
        selectedWallpaper !== null &&
        !selectedIsActive
    readonly property var categories: [
        { name: Translation.tr("All"), code: "111" },
        { name: Translation.tr("General"), code: "100" },
        { name: "Anime", code: "010" },
        { name: Translation.tr("People"), code: "001" }
    ]
    readonly property var sortOptions: [
        { name: Translation.tr("Latest"), code: "date_added" },
        { name: Translation.tr("Relevance"), code: "relevance" },
        { name: Translation.tr("Popular"), code: "views" },
        { name: Translation.tr("Favorites"), code: "favorites" },
        { name: Translation.tr("Random"), code: "random" }
    ]
    readonly property var resolutions: [
        { name: Translation.tr("Any resolution"), code: "" },
        { name: "1920 × 1080+", code: "1920x1080" },
        { name: "2560 × 1440+", code: "2560x1440" },
        { name: "3840 × 2160+", code: "3840x2160" }
    ]
    readonly property var purityOptions: [
        { name: "SFW", code: "100" },
        { name: "SFW + Sketchy", code: "110" },
        { name: Translation.tr("All (NSFW)"), code: "111" }
    ]
    function normalizedPath(path) {
        return WallpaperUtils.normalizedPath(path);
    }
    function cachedPathFor(item) {
        return WallpaperUtils.cachedPathFor(cachedPaths, item);
    }
    function isItemActive(item) {
        return WallpaperUtils.isItemActive(cachedPaths, item, activeWallpaperPath);
    }
    function updateCachedPath(id, path) {
        cachedPaths = WallpaperUtils.withCachedPath(cachedPaths, id, path);
    }
    function formatBytes(value) {
        const bytes = Math.max(0, Number(value) || 0);
        if (bytes >= 1024 * 1024)
            return (bytes / (1024 * 1024)).toFixed(1) + " MB";
        if (bytes >= 1024)
            return (bytes / 1024).toFixed(1) + " KB";
        return Math.round(bytes) + " B";
    }
    function progressDescription() {
        const current = formatBytes(downloadedBytes);
        if (downloadTotalBytes > 0) {
            return current + " / " +
                formatBytes(downloadTotalBytes);
        }
        return current + " transferidos";
    }
    function resetDownloadProgress() {
        const progress = WallpaperDownloadState.reset();
        downloadPercentage = progress.percent;
        downloadedBytes = progress.received;
        downloadTotalBytes = progress.total;
        downloadCompleted = false;
        downloadCancelling = false;
    }
    function indexOfCode(items, code) {
        for (let i = 0; i < items.length; i++) {
            if (items[i].code === code)
                return i;
        }
        return -1;
    }
    function providerIndex(code) {
        return indexOfCode(availableProviders, code);
    }
    // Páginas visíveis: primeira, vizinhas e última, com reticências.
    function visiblePageNumbers() {
        return WallpaperPagination.visiblePages(page, lastPage, true);
    }
    function changePage(targetPage) {
        if (busy || !providersLoaded ||
            targetPage < 1 || targetPage > lastPage ||
            targetPage === page)
            return;
        page = targetPage;
        search(false);
    }
    function clearSelection() {
        selectedWallpaper = null;
        selectedId = "";
    }
    function selectWallpaper(item) {
        if (busy || !item)
            return;
        if (selectedId === item.id) {
            clearSelection();
            return;
        }
        selectedWallpaper = item;
        selectedId = item.id;
        hasError = false;
        feedback = "";
    }
    function refreshProviders() {
        if (busy)
            return;
        providersLoaded = false;
        clearSelection();
        results = [];
        cachedPaths = ({});
        page = 1;
        lastPage = 1;
        hasError = false;
        feedback = "Atualizando provedores...";
        if (providerControllerLoader.item === null) {
            hasError = true;
            feedback = "Controlador de provedores indisponível.";
            return;
        }
        providerControllerLoader.item.start(
            WallpaperCommands.providers(scriptPath, purity, false)
        );
    }
    function changePurity(code) {
        if (busy || purity === code)
            return;
        purity = code;
        category = "111";
        refreshProviders();
    }
    function changeProvider(code) {
        if (
            busy ||
            provider === code ||
            providerIndex(code) === -1
        ) {
            return;
        }
        provider = code;
        category = "111";
        search(true);
    }
    function clearSearch() {
        if (root.busy || !root.providersLoaded || searchField.text.length === 0)
            return;
        searchField.text = "";
        root.search(true);
    }
    function search(resetPage) {
        if (busy || !providersLoaded)
            return;
        if (providerIndex(provider) === -1) {
            hasError = true;
            feedback = "Nenhum provedor disponível.";
            return;
        }
        if (resetPage)
            page = 1;
        hasError = false;
        feedback = "Pesquisando wallpapers...";
        if (searchControllerLoader.item === null) {
            hasError = true;
            feedback = "Controlador de pesquisa indisponível.";
            return;
        }
        searchControllerLoader.item.start(
            WallpaperCommands.searchStatic(
                scriptPath, provider, searchField.text, category,
                sorting, resolution, purity, page
            )
        );
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
        checkingCache = true;
        if (cacheLoader.item === null) {
            checkingCache = false;
            console.warn("[WallpaperCache] Controlador indisponível.");
            return;
        }
        cacheLoader.item.start(scriptPath, provider, ids);
    }
    function applySelected() {
        if (!canApply)
            return;
        if (selectedCachedPath.length > 0) {
            Wallpapers.apply(selectedCachedPath);
            feedback = "Wallpaper local enviado para aplicação.";
            hasError = false;
            return;
        }
        const item = selectedWallpaper;
        if (!item.url || !item.id || !item.provider)
            return;
        resetDownloadProgress();
        downloadLifecycle = WallpaperDownloadLifecycle.start();
        hasError = false;
        feedback = "Iniciando download...";
        downloadController.item.requestedId = item.id;
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
            "--progress"
        ], item.id);
    }
    function cancelDownload() {
        if (!(downloadController.item !== null && downloadController.item.running) || downloadCancelling)
            return;
        downloadCancelling = true;
        downloadLifecycle = WallpaperDownloadLifecycle.cancel(downloadLifecycle);
        hasError = false;
        feedback = "Cancelando download...";
        downloadController.item.cancel();
    }
    function handleDownloadLine(line) {
        const parsed = WallpaperDownloadEvents.parseLine(line);
        if (parsed.empty)
            return;
        if (!parsed.valid) {
            console.warn(
                "[WallpaperBrowser] Invalid download event:",
                parsed.raw
            );
            return;
        }
        const data = parsed.data;
        downloadLifecycle = WallpaperDownloadLifecycle.event(downloadLifecycle, data);
        if (downloadCancelling)
            return;
        if (data.event === "started") {
            const progress = WallpaperDownloadState.staticStarted(data);
            downloadTotalBytes = progress.total;
            downloadedBytes = progress.received;
            downloadPercentage = progress.percent;
            feedback = "Baixando wallpaper...";
            return;
        }
        if (data.event === "progress") {
            const progress = WallpaperDownloadState.staticProgress(data);
            downloadedBytes = progress.received;
            downloadTotalBytes = progress.total;
            downloadPercentage = progress.percent;
            feedback = "Baixando wallpaper...";
            return;
        }
        if (data.event === "cached") {
            feedback = "Wallpaper encontrado no cache.";
            return;
        }
        if (data.ok === true && data.path) {
            downloadCompleted = true;
            updateCachedPath(
                downloadController.item.requestedId,
                String(data.path)
            );
            Wallpapers.apply(String(data.path));
            hasError = false;
            feedback = data.cached === true
                ? "Wallpaper do cache enviado para aplicação."
                : "Wallpaper baixado e enviado para aplicação.";
            return;
        }
        if (data.ok === false) {
            hasError = !data.cancelled;
            feedback = data.error || "Falha no download.";
        }
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
    function handleProvidersCompleted(validProviders) {
        root.availableProviders = validProviders;
        root.providersLoaded = true;
        if (validProviders.length === 0) {
            root.hasError = true;
            root.feedback = "Nenhum provedor disponível para este conteúdo.";
            return;
        }
        if (root.providerIndex(root.provider) === -1)
            root.provider = validProviders[0].code;
        root.hasError = false;
        root.feedback = "";
        initialSearchTimer.restart();
    }
    function handleProvidersFailed(message, details) {
        root.availableProviders = [];
        root.providersLoaded = false;
        root.results = [];
        root.cachedPaths = ({});
        root.hasError = true;
        root.feedback = "Erro ao carregar provedores: " + message;
        if (details.length > 0)
            console.warn("[WallpaperBrowser] Providers:", details);
    }
    Timer {
        id: initialSearchTimer
        interval: 0
        repeat: false
        onTriggered: root.search(true)
    }
    Loader {
        id: searchControllerLoader
        active: true
        source: "../controllers/WallpaperSearchController.qml"
        onLoaded: {
            item.completed.connect(root.handleSearchCompleted);
            item.failed.connect(root.handleSearchFailed);
        }
    }
    function handleSearchCompleted(items, lastPage) {
        root.clearSelection();
        root.cachedPaths = ({});
        root.checkingCache = false;
        root.results = items;
        root.lastPage = lastPage;
        root.lastSuccessfulPage = root.page;
        root.hasError = false;
        root.feedback = root.results.length > 0
            ? ""
            : "Nenhum wallpaper encontrado.";
        grid.positionViewAtBeginning();
        root.refreshCacheBatch();
    }
    function handleSearchFailed(message, details) {
        root.page = root.lastSuccessfulPage;
        root.hasError = true;
        root.feedback = "Erro na pesquisa: " + message;
        if (details.length > 0)
            console.warn("[WallpaperBrowser] Search:", details);
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

    Loader {
        id: downloadController
        active: true
        source: "../controllers/WallpaperDownloadController.qml"
        onLoaded: {
            item.lineReceived.connect(root.handleDownloadLine);
            item.finished.connect(root.handleDownloadExited);
        }
    }
    function handleDownloadExited(exitCode, details) {
        const outcome = WallpaperDownloadLifecycle.terminal(
            root.downloadLifecycle, exitCode, root.downloadCompleted, false
        );
        root.downloadLifecycle = outcome.state;
        const actions = WallpaperDownloadLifecycle.finishActions(outcome);
        if (actions.clearCancellation) {
            root.downloadCancelling = false;
            root.downloadPercentage = -1;
            root.downloadedBytes = 0;
            root.downloadTotalBytes = 0;
            root.hasError = false;
            root.feedback = "Download cancelado.";
            return;
        }
        if (actions.applyResult) {
            root.downloadCompleted = false;
            return;
        }
        if (actions.reportFailure && exitCode !== 0) {
            root.hasError = true;
            if (!root.feedback ||
                root.feedback === "Baixando wallpaper..." ||
                root.feedback === "Iniciando download...") {
                root.feedback = "Falha no download. Consulte os logs.";
            }
            if (details.length > 0)
                console.warn("[WallpaperBrowser] Download:", details);
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 8
            StyledComboBox {
                id: providerSelector
                Layout.preferredWidth: 160
                Layout.minimumWidth: 110
                enabled:
                    !root.busy &&
                    root.providersLoaded &&
                    root.availableProviders.length > 0
                buttonIcon: "public"
                textRole: "name"
                model: root.availableProviders
                currentIndex: root.providerIndex(
                    root.provider
                )
                onActivated: index => {
                    if (
                        index >= 0 &&
                        index < root.availableProviders.length
                    ) {
                        root.changeProvider(
                            root.availableProviders[index].code
                        );
                    }
                }
            }
            MaterialTextField {
                id: searchField
                Layout.fillWidth: true
                Layout.minimumWidth: 100
                Layout.preferredHeight: 48
                placeholderText: Translation.tr("Search wallpapers...")
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
            Layout.minimumWidth: 0
            spacing: 8
            StyledComboBox {
                id: categorySelector
                Layout.fillWidth: true
                Layout.minimumWidth: 100
                enabled:
                    !root.busy &&
                    root.provider === "wallhaven"
                buttonIcon: "category"
                textRole: "name"
                model: root.categories
                currentIndex: root.indexOfCode(
                    root.categories,
                    root.category
                )
                onActivated: index => {
                    root.category =
                        root.categories[index].code;
                    root.search(true);
                }
            }
            StyledComboBox {
                id: sortingSelector
                Layout.fillWidth: true
                Layout.minimumWidth: 100
                enabled: !root.busy
                buttonIcon: "sort"
                textRole: "name"
                model: root.sortOptions
                currentIndex: root.indexOfCode(
                    root.sortOptions,
                    root.sorting
                )
                onActivated: index => {
                    root.sorting =
                        root.sortOptions[index].code;
                    root.search(true);
                }
            }
            StyledComboBox {
                id: resolutionSelector
                Layout.fillWidth: true
                Layout.minimumWidth: 100
                enabled: !root.busy
                buttonIcon: "aspect_ratio"
                textRole: "name"
                model: root.resolutions
                currentIndex: root.indexOfCode(
                    root.resolutions,
                    root.resolution
                )
                onActivated: index => {
                    root.resolution =
                        root.resolutions[index].code;
                    root.search(true);
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "visibility"
                    iconSize: 20
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    text: Translation.tr("Content")
                    color: Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 16
                    Repeater {
                model: root.purityOptions
                delegate: RowLayout {
                    id: purityOption
                    required property var modelData
                    spacing: 6
                    readonly property bool selected: root.purity === modelData.code
                    readonly property bool available: !root.busy
                    opacity: available ? 1 : 0.5

                    StyledText {
                        text: purityOption.modelData.name
                        color: Appearance.colors.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    Rectangle {
                        id: purityTrack
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 22
                        radius: height / 2
                        color: purityOption.selected
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colLayer2
                        border.width: purityOption.selected ? 0 : 1
                        border.color: Appearance.colors.colOnSurfaceVariant

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 8
                            y: 3
                            x: purityOption.selected ? purityTrack.width - width - 3 : 3
                            color: purityOption.selected
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnSurfaceVariant
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        HoverHandler {
                            id: purityHover
                            enabled: purityOption.available
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            enabled: purityOption.available
                            onTapped: root.changePurity(purityOption.modelData.code)
                        }
                    }
                }
            }
                Item { Layout.fillWidth: true }
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible:
                root.providersLoaded &&
                root.provider !== "wallhaven"
            text: Translation.tr("Konachan and Yande.re specialize in anime. The general category filter does not apply to these sources.")
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Layout.minimumHeight: 24
            Layout.preferredHeight: 24
            Layout.maximumHeight: 24
            visible: true
            opacity: root.feedback.length > 0 ? 1 : 0
            MaterialSymbol {
                text: root.hasError
                    ? "error"
                    : root.busy
                        ? "progress_activity"
                        : "check_circle"
                iconSize: 18
                color: root.hasError
                    ? Appearance.colors.colError
                    : Appearance.colors.colOnSurface
            }
            StyledText {
                Layout.fillWidth: true
                text: SettingsMessages.translate(root.feedback, Translation.tr)
                wrapMode: Text.Wrap
                color: root.hasError
                    ? Appearance.colors.colError
                    : Appearance.colors.colOnSurface
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredHeight: 360
            clip: true
            readonly property int columns: Math.max(
                1,
                Math.floor(width / 170)
            )
            cellWidth: width / columns
            cellHeight: 120
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
                    "live": false
                })

                onLoaded: {
                    item.wallpaper = Qt.binding(() => cardLoader.modelData);
                    item.selected = Qt.binding(() => root.selectedId !== "" && root.selectedId === cardLoader.modelData.id);
                    item.cached = Qt.binding(() => root.cachedPathFor(cardLoader.modelData).length > 0);
                    item.active = Qt.binding(() => root.isItemActive(cardLoader.modelData));
                    item.busy = Qt.binding(() => root.busy);
                    item.activated.connect(() => root.selectWallpaper(cardLoader.modelData));
                }
            }
        }
        // Progress panel, visible only during downloads.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 7
            visible:
                (downloadController.item !== null && downloadController.item.running) ||
                root.downloadCancelling
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "download"
                    iconSize: 19
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: SettingsMessages.translate(root.downloadCancelling
                        ? "Cancelando transferência..."
                        : root.progressDescription(), Translation.tr)
                    color: Appearance.colors.colOnSurface
                    font.pixelSize:
                        Appearance.font.pixelSize.small
                }
                StyledText {
                    visible:
                        root.downloadPercentage >= 0 &&
                        !root.downloadCancelling
                    text: root.downloadPercentage + "%"
                    color: Appearance.colors.colPrimary
                    font.pixelSize:
                        Appearance.font.pixelSize.small
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: Appearance.colors.colLayer2
                clip: true
                Rectangle {
                    id: progressFill
                    height: parent.height
                    radius: parent.radius
                    color: Appearance.colors.colPrimary
                    width: root.downloadPercentage >= 0
                        ? parent.width *
                            root.downloadPercentage / 100
                        : parent.width * 0.25
                    Behavior on width {
                        NumberAnimation {
                            duration: 100
                        }
                    }
                    SequentialAnimation on x {
                        running:
                            (downloadController.item !== null && downloadController.item.running) &&
                            root.downloadPercentage < 0 &&
                            !root.downloadCancelling
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0
                            to: progressFill.parent.width -
                                progressFill.width
                            duration: 850
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            from: progressFill.parent.width -
                                progressFill.width
                            to: 0
                            duration: 850
                            easing.type: Easing.InOutQuad
                        }
                        onStopped: progressFill.x = 0
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 8

            // Paginação em uma única linha: Anterior, páginas e Próxima.
            // A página 1 já está sempre disponível nos números.
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

                            readonly property bool current:
                                modelData === root.page
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
                                    ? "…" : String(pageButton.modelData)
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
                    enabled: (downloadController.item !== null && downloadController.item.running)
                        ? !root.downloadCancelling
                        : root.canApply
                    materialIcon: (downloadController.item !== null && downloadController.item.running)
                        ? "close"
                        : root.selectedIsActive
                            ? "check_circle"
                            : root.selectedCachedPath.length > 0
                                ? "wallpaper"
                                : "download"
                    mainText: SettingsMessages.translate(root.downloadCancelling
                        ? "Cancelando..."
                        : (downloadController.item !== null && downloadController.item.running)
                            ? "Cancelar"
                            : root.checkingCache
                                ? "Verificando..."
                                : root.selectedIsActive
                                    ? "Em uso"
                                    : root.selectedCachedPath.length > 0
                                        ? "Aplicar"
                                        : "Baixar e aplicar", Translation.tr)
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover:
                        Appearance.colors.colPrimaryContainerHover
                    colRipple:
                        Appearance.colors.colPrimaryContainerActive
                    onClicked: {
                        if ((downloadController.item !== null && downloadController.item.running))
                            root.cancelDownload();
                        else
                            root.applySelected();
                    }
                }
            }
        }
    }
    Component.onCompleted: root.refreshProviders()
}
