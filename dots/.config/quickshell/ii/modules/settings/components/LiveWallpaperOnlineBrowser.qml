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
    Layout.minimumWidth: 0
    readonly property string scriptPath: Quickshell.shellPath(
        "scripts/wallpaper/live/live_wallpaper.py"
    )
    property var providers: []
    property var results: []
    property var selectedWallpaper: null
    property string provider: "desktophut"
    property int page: 1
    property int lastPage: 1
    property bool totalKnown: false
    property string feedback: ""
    property bool hasError: false
    property bool providersLoaded: false
    property var cachedPaths: ({})
    property string cachedPath: ""
    property bool checkingCache: false
    property bool cacheBatchPending: false
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
        if (
            selectedWallpaper !== null &&
            selectedWallpaper.id === id
        ) {
            cachedPath = String(path || "");
        }
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
            cachedPath = cachedPathFor(item);
            if (
                !cacheBatchPending &&
                !batchProc.running &&
                cachedPath.length === 0
            ) {
                checkSelectedCache();
            } else {
                checkingCache =
                    cacheBatchPending || batchProc.running;
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
            totalKnown = false;
        }
        clearSelection();
        cachedPaths = ({});
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
    // O backend atual só confirma a existência
    // da próxima página. Não inventamos um total.
    function visiblePageNumbers() {
        const maxPage = Math.max(page, lastPage);
        const selected = {};
        selected[1] = true;
        for (
            let number = Math.max(1, page - 1);
            number <= Math.min(maxPage, page + 1);
            number++
        ) {
            selected[number] = true;
        }
        if (totalKnown)
            selected[maxPage] = true;
        const numbers = Object.keys(selected)
            .map(value => Number(value))
            .sort((a, b) => a - b);
        const display = [];
        for (let i = 0; i < numbers.length; i++) {
            if (
                i > 0 &&
                numbers[i] - numbers[i - 1] > 1
            ) {
                display.push(-1);
            }
            display.push(numbers[i]);
        }
        return display;
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
            downloadParseError =
                "Resposta de download inválida.";
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
            downloadPercent =
                data.percent === null ||
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
                        data.error ||
                        "Falha ao carregar provedores."
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
                // Os provedores atuais informam somente
                // se existe uma próxima página.
                root.totalKnown =
                    root.lastPage <= root.page;
                root.hasError = false;
                root.feedback = root.results.length > 0
                    ? ""
                    : "Nenhum wallpaper encontrado.";
                grid.positionViewAtBeginning();
                root.refreshCacheBatch();
            } catch (error) {
                root.results = [];
                root.cachedPaths = ({});
                root.lastPage = root.page;
                root.totalKnown = false;
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
                        "Falha na consulta em lote."
                    );
                }
                const paths = {};
                const items = data.items || {};
                for (const id of Object.keys(items)) {
                    if (items[id].cached && items[id].path)
                        paths[id] = String(items[id].path);
                }
                root.cachedPaths = paths;
                if (root.selectedWallpaper !== null) {
                    root.cachedPath = root.cachedPathFor(
                        root.selectedWallpaper
                    );
                }
                root.checkingCache = false;
            } catch (error) {
                console.warn(
                    "[LiveWallpaperOnlineBrowser] Cache em lote:",
                    error.message,
                    batchErrors.text
                );
                root.checkingCache = false;
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
                const path = String(data.path);
                if (root.selectedWallpaper !== null) {
                    root.updateCachedPath(
                        root.selectedWallpaper.id,
                        path
                    );
                }
                root.downloadStage = "";
                root.hasError = false;
                Wallpapers.apply(path);
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
        Layout.minimumWidth: 0
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
            delegate: Item {
                id: wallpaperDelegate
                required property var modelData
                readonly property bool isSelected:
                    root.selectedWallpaper !== null &&
                    root.selectedWallpaper.id === modelData.id
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
                            wallpaperDelegate.localPath.length > 0
                        width: cachedLabel.implicitWidth + 16
                        height: 25
                        radius: Appearance.rounding.small
                        color:
                            wallpaperDelegate.isActive
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colPrimaryContainer
                        Row {
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
                                id: cachedLabel
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
                    MaterialSymbol {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 8
                        visible: wallpaperDelegate.isSelected
                        text: "check_circle"
                        iconSize: 25
                        color: Appearance.colors.colPrimary
                    }
                    HoverHandler {
                        id: hoverHandler
                        enabled: !root.busy
                        cursorShape: Qt.PointingHandCursor
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
