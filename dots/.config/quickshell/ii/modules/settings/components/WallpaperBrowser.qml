import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services
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
        providerProc.running ||
        searchProc.running ||
        downloadProc.running ||
        downloadCancelling
    readonly property bool canApply:
        !busy &&
        !checkingCache &&
        selectedWallpaper !== null &&
        !selectedIsActive
    readonly property var categories: [
        { name: "Todas", code: "111" },
        { name: "Geral", code: "100" },
        { name: "Anime", code: "010" },
        { name: "Pessoas", code: "001" }
    ]
    readonly property var sortOptions: [
        { name: "Recentes", code: "date_added" },
        { name: "Relevância", code: "relevance" },
        { name: "Populares", code: "views" },
        { name: "Favoritos", code: "favorites" },
        { name: "Aleatórios", code: "random" }
    ]
    readonly property var resolutions: [
        { name: "Qualquer resolução", code: "" },
        { name: "1920 × 1080+", code: "1920x1080" },
        { name: "2560 × 1440+", code: "2560x1440" },
        { name: "3840 × 2160+", code: "3840x2160" }
    ]
    readonly property var purityOptions: [
        { name: "SFW", code: "100" },
        { name: "SFW + Sketchy", code: "110" },
        { name: "Todos (NSFW)", code: "111" }
    ]
    function normalizedPath(path) {
        let value = String(path || "");
        if (value.startsWith("file://"))
            value = decodeURIComponent(value.substring(7));
        return value.replace(/\/+$/, "");
    }
    function cachedPathFor(item) {
        if (!item || !item.id)
            return "";
        return String(cachedPaths[item.id] || "");
    }
    function isItemActive(item) {
        const path = cachedPathFor(item);
        return path.length > 0 &&
            normalizedPath(path) ===
                normalizedPath(activeWallpaperPath);
    }
    function updateCachedPath(id, path) {
        const updated = Object.assign({}, cachedPaths);
        if (path && String(path).length > 0)
            updated[id] = String(path);
        else
            delete updated[id];
        cachedPaths = updated;
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
        downloadPercentage = -1;
        downloadedBytes = 0;
        downloadTotalBytes = 0;
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
        const maxPage = Math.max(page, lastPage);
        const selected = {};
        selected[1] = true;
        for (let number = Math.max(1, page - 1);
             number <= Math.min(maxPage, page + 1);
             number++) {
            selected[number] = true;
        }
        selected[maxPage] = true;
        const numbers = Object.keys(selected)
            .map(value => Number(value))
            .sort((a, b) => a - b);
        const display = [];
        for (let i = 0; i < numbers.length; i++) {
            if (i > 0 && numbers[i] - numbers[i - 1] > 1)
                display.push(-1);
            display.push(numbers[i]);
        }
        return display;
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
        providerProc.command = [
            "python3",
            scriptPath,
            "providers",
            "--purity",
            purity
        ];
        providerProc.running = true;
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
    function search(resetPage) {
        if (busy || !providersLoaded)
            return;
        if (providerIndex(provider) === -1) {
            hasError = true;
            feedback = "Nenhum provedor disponível.";
            return;
        }
        if (resetPage) {
            page = 1;
            lastPage = 1;
        }
        clearSelection();
        cachedPaths = ({});
        checkingCache = false;
        hasError = false;
        feedback = "Pesquisando wallpapers...";
        searchProc.command = [
            "python3",
            scriptPath,
            "search",
            "--provider",
            provider,
            "--query",
            searchField.text,
            "--categories",
            category,
            "--sorting",
            sorting,
            "--resolutions",
            resolution,
            "--purity",
            purity,
            "--page",
            String(page)
        ];
        searchProc.running = true;
    }
    function refreshCacheBatch() {
        if (batchProc.running) {
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
        batchProc.requestedProvider = provider;
        batchProc.requestedIds = ids.join(",");
        batchProc.command = [
            "python3",
            scriptPath,
            "status-batch",
            "--provider",
            provider,
            "--image-ids"
        ].concat(ids);
        batchProc.running = true;
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
        hasError = false;
        feedback = "Iniciando download...";
        downloadProc.requestedId = item.id;
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
            "--progress"
        ];
        downloadProc.running = true;
    }
    function cancelDownload() {
        if (!downloadProc.running || downloadCancelling)
            return;
        downloadCancelling = true;
        hasError = false;
        feedback = "Cancelando download...";
        downloadProc.running = false;
    }
    function handleDownloadLine(line) {
        const value = String(line || "").trim();
        if (!value)
            return;
        let data;
        try {
            data = JSON.parse(value);
        } catch (error) {
            console.warn(
                "[WallpaperBrowser] Invalid download event:",
                value
            );
            return;
        }
        if (downloadCancelling)
            return;
        if (data.event === "started") {
            downloadTotalBytes = Math.max(
                0,
                Number(data.total) || 0
            );
            downloadPercentage = downloadTotalBytes > 0
                ? 0
                : -1;
            feedback = "Baixando wallpaper...";
            return;
        }
        if (data.event === "progress") {
            downloadedBytes = Math.max(
                0,
                Number(data.downloaded) || 0
            );
            downloadTotalBytes = Math.max(
                0,
                Number(data.total) || 0
            );
            downloadPercentage =
                Number(data.percentage) >= 0
                    ? Math.min(
                        100,
                        Number(data.percentage)
                    )
                    : -1;
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
                downloadProc.requestedId,
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
                        data.error ||
                        "Falha ao consultar provedores."
                    );
                }
                if (!Array.isArray(data.providers)) {
                    throw new Error(
                        "Lista de provedores inválida."
                    );
                }
                const validProviders = data.providers.filter(
                    item =>
                        item &&
                        typeof item.code === "string" &&
                        typeof item.name === "string"
                );
                root.availableProviders = validProviders;
                root.providersLoaded = true;
                if (validProviders.length === 0) {
                    root.hasError = true;
                    root.feedback =
                        "Nenhum provedor disponível para este conteúdo.";
                    return;
                }
                if (root.providerIndex(root.provider) === -1)
                    root.provider = validProviders[0].code;
                root.hasError = false;
                root.feedback = "";
                initialSearchTimer.restart();
            } catch (error) {
                root.availableProviders = [];
                root.providersLoaded = false;
                root.results = [];
                root.cachedPaths = ({});
                root.hasError = true;
                root.feedback =
                    "Erro ao carregar provedores: " +
                    error.message;
                const details = providerErrors.text.trim();
                if (details.length > 0) {
                    console.warn(
                        "[WallpaperBrowser] Providers:",
                        details
                    );
                }
            }
        }
    }
    Timer {
        id: initialSearchTimer
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
                const incoming = Array.isArray(data.items)
                    ? data.items : [];
                const seenIds = {};
                const seenUrls = {};
                root.results = incoming.filter(item => {
                    if (!item || !item.id || !item.thumb)
                        return false;
                    const id = String(item.id);
                    const url = String(item.url || "");
                    if (seenIds[id] || (url && seenUrls[url]))
                        return false;
                    seenIds[id] = true;
                    if (url)
                        seenUrls[url] = true;
                    return true;
                });
                root.lastPage = Math.max(
                    1,
                    Number(data.last_page) || 1
                );
                root.hasError = false;
                root.feedback = root.results.length > 0
                    ? ""
                    : "Nenhum wallpaper encontrado.";
                grid.positionViewAtBeginning();
                root.refreshCacheBatch();
            } catch (error) {
                root.results = [];
                root.cachedPaths = ({});
                root.checkingCache = false;
                root.hasError = true;
                root.feedback =
                    "Erro na pesquisa: " + error.message;
                const details = searchErrors.text.trim();
                if (details.length > 0) {
                    console.warn(
                        "[WallpaperBrowser] Search:",
                        details
                    );
                }
            }
        }
    }
    Process {
        id: batchProc
        running: false
        property string requestedProvider: ""
        property string requestedIds: ""
        stdout: StdioCollector {
            id: batchOutput
        }
        stderr: StdioCollector {
            id: batchErrors
        }
        onExited: (exitCode, exitStatus) => {
            const currentIds = root.results
                .map(item => String(item.id || ""))
                .filter(id => id.length > 0)
                .filter((id, index, array) =>
                    array.indexOf(id) === index)
                .join(",");
            if (
                root.cacheBatchPending ||
                requestedProvider !== root.provider ||
                requestedIds !== currentIds
            ) {
                root.refreshCacheBatch();
                return;
            }
            try {
                const data = JSON.parse(
                    batchOutput.text.trim()
                );
                if (exitCode !== 0 || data.ok !== true) {
                    throw new Error(
                        data.error ||
                        "Falha na consulta de cache."
                    );
                }
                const paths = {};
                const items = data.items || {};
                for (const id of Object.keys(items)) {
                    if (items[id].cached && items[id].path)
                        paths[id] = String(items[id].path);
                }
                root.cachedPaths = paths;
                root.checkingCache = false;
            } catch (error) {
                root.checkingCache = false;
                console.warn(
                    "[WallpaperBrowser] Cache:",
                    error.message,
                    batchErrors.text
                );
            }
        }
    }
    Process {
        id: downloadProc
        running: false
        property string requestedId: ""
        stdout: SplitParser {
            onRead: data => root.handleDownloadLine(data)
        }
        stderr: StdioCollector {
            id: downloadErrors
        }
        onExited: (exitCode, exitStatus) => {
            if (root.downloadCancelling) {
                root.downloadCancelling = false;
                root.downloadPercentage = -1;
                root.downloadedBytes = 0;
                root.downloadTotalBytes = 0;
                root.hasError = false;
                root.feedback = "Download cancelado.";
                return;
            }
            if (root.downloadCompleted) {
                root.downloadCompleted = false;
                return;
            }
            if (exitCode !== 0) {
                root.hasError = true;
                if (!root.feedback ||
                    root.feedback === "Baixando wallpaper..." ||
                    root.feedback === "Iniciando download...") {
                    root.feedback =
                        "Falha no download. Consulte os logs.";
                }
                const details = downloadErrors.text.trim();
                if (details.length > 0) {
                    console.warn(
                        "[WallpaperBrowser] Download:",
                        details
                    );
                }
            }
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
                placeholderText: "Pesquisar wallpapers..."
                onAccepted: root.search(true)
            }
            RippleButtonWithIcon {
                Layout.preferredHeight: 48
                enabled:
                    !root.busy &&
                    root.providersLoaded
                buttonRadius: Appearance.rounding.small
                materialIcon: "search"
                mainText: "Pesquisar"
                onClicked: root.search(true)
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
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 8
            MaterialSymbol {
                text: "visibility"
                iconSize: 20
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                text: "Conteúdo"
                color: Appearance.colors.colOnSurface
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledComboBox {
                id: puritySelector
                Layout.preferredWidth: 210
                Layout.minimumWidth: 150
                enabled: !root.busy
                buttonIcon: "filter_alt"
                textRole: "name"
                model: root.purityOptions
                currentIndex: root.indexOfCode(
                    root.purityOptions,
                    root.purity
                )
                onActivated: index => {
                    root.changePurity(
                        root.purityOptions[index].code
                    );
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible:
                root.providersLoaded &&
                root.provider !== "wallhaven"
            text:
                "Konachan e Yande.re são especializados em anime. " +
                "O filtro de categoria geral não se aplica a essas fontes."
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
                text: root.feedback
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
            delegate: Item {
                id: wallpaperDelegate
                required property var modelData
                readonly property bool isSelected:
                    root.selectedId !== "" &&
                    root.selectedId === modelData.id
                readonly property string localPath:
                    root.cachedPathFor(modelData)
                readonly property bool isActive:
                    root.isItemActive(modelData)
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
                            thumbnail.status === Image.Loading
                        text: "image"
                        iconSize: 28
                        color: Appearance.colors.colOnSurface
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: Appearance.colors.colPrimary
                        opacity: wallpaperDelegate.isSelected
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
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 6
                        visible:
                            wallpaperDelegate.localPath.length > 0
                        width: cacheBadgeRow.implicitWidth + 14
                        height: 25
                        radius: Appearance.rounding.small
                        color: wallpaperDelegate.isActive
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colPrimaryContainer
                        Row {
                            id: cacheBadgeRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: wallpaperDelegate.isActive
                                    ? "check_circle"
                                    : "download_done"
                                iconSize: 14
                                color: wallpaperDelegate.isActive
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnPrimaryContainer
                            }
                            StyledText {
                                text: wallpaperDelegate.isActive
                                    ? "Em uso"
                                    : "Já baixado"
                                color: wallpaperDelegate.isActive
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnPrimaryContainer
                                font.pixelSize:
                                    Appearance.font.pixelSize.smaller
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
                        visible: wallpaperDelegate.isSelected
                        color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 30
                        color: "#99000000"
                        StyledText {
                            anchors.centerIn: parent
                            text:
                                wallpaperDelegate.modelData.resolution || ""
                            color: "white"
                            font.pixelSize:
                                Appearance.font.pixelSize.smaller
                        }
                    }
                    HoverHandler {
                        id: hoverHandler
                        cursorShape: root.busy
                            ? Qt.ArrowCursor
                            : Qt.PointingHandCursor
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
        // Progress panel, visible only during downloads.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 7
            visible:
                downloadProc.running ||
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
                    text: root.downloadCancelling
                        ? "Cancelando transferência..."
                        : root.progressDescription()
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
                            downloadProc.running &&
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
                    mainText: "Anterior"
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
                    mainText: "Próxima"
                    buttonRadius: Appearance.rounding.small
                    onClicked: root.changePage(root.page + 1)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Item { Layout.fillWidth: true }

                RippleButtonWithIcon {
                    enabled: downloadProc.running
                        ? !root.downloadCancelling
                        : root.canApply
                    materialIcon: downloadProc.running
                        ? "close"
                        : root.selectedIsActive
                            ? "check_circle"
                            : root.selectedCachedPath.length > 0
                                ? "wallpaper"
                                : "download"
                    mainText: root.downloadCancelling
                        ? "Cancelando..."
                        : downloadProc.running
                            ? "Cancelar"
                            : root.checkingCache
                                ? "Verificando..."
                                : root.selectedIsActive
                                    ? "Em uso"
                                    : root.selectedCachedPath.length > 0
                                        ? "Aplicar"
                                        : "Baixar e aplicar"
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover:
                        Appearance.colors.colPrimaryContainerHover
                    colRipple:
                        Appearance.colors.colPrimaryContainerActive
                    onClicked: {
                        if (downloadProc.running)
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
