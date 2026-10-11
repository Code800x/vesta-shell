
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
        downloadProc.running

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

        if (resetPage)
            page = 1;

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

        hasError = false;
        feedback = "Baixando wallpaper selecionado...";

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
            item.id
        ];

        downloadProc.running = true;
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

                root.results = data.items || [];

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

                root.updateCachedPath(
                    requestedId,
                    String(data.path)
                );

                Wallpapers.apply(data.path);

                root.hasError = false;
                root.feedback = data.cached === true
                    ? "Wallpaper do cache enviado para aplicação."
                    : "Wallpaper baixado e enviado para aplicação.";

            } catch (error) {
                root.hasError = true;
                root.feedback =
                    "Erro no download: " + error.message;

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
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledComboBox {
                id: providerSelector

                Layout.preferredWidth: 160

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
            spacing: 8

            StyledComboBox {
                id: categorySelector

                Layout.fillWidth: true

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

            visible: root.feedback.length > 0

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
            Layout.preferredHeight: 420

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

                    // Indicador do cache em todos os cards.
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

                            color:
                                Appearance.colors.colOnPrimary
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

                onClicked: {
                    root.page--;
                    root.search(false);
                }
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

                onClicked: {
                    root.page++;
                    root.search(false);
                }
            }

            Item {
                Layout.fillWidth: true
            }

            RippleButtonWithIcon {
                enabled: root.canApply

                materialIcon: downloadProc.running
                    ? "progress_activity"
                    : root.selectedIsActive
                        ? "check_circle"
                        : root.selectedCachedPath.length > 0
                            ? "wallpaper"
                            : "download"

                mainText: downloadProc.running
                    ? "Baixando..."
                    : root.checkingCache
                        ? "Verificando..."
                        : root.selectedIsActive
                            ? "Em uso"
                            : root.selectedCachedPath.length > 0
                                ? "Aplicar"
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

    Component.onCompleted: root.refreshProviders()
}
