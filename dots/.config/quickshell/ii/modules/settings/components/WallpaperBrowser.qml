
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

    readonly property bool busy:
        providerProc.running ||
        searchProc.running ||
        downloadProc.running

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

    function indexOfCode(items, code) {
        for (let i = 0; i < items.length; i++) {
            if (items[i].code === code)
                return i;
        }

        return -1;
    }

    function providerIndex(code) {
        return root.indexOfCode(root.availableProviders, code);
    }

    function clearSelection() {
        root.selectedWallpaper = null;
        root.selectedId = "";
    }

    function selectWallpaper(item) {
        if (root.busy || !item)
            return;

        if (root.selectedId === item.id) {
            root.clearSelection();
            return;
        }

        root.selectedWallpaper = item;
        root.selectedId = item.id;
        root.hasError = false;
        root.feedback = "";
    }

    function refreshProviders() {
        if (root.busy)
            return;

        root.providersLoaded = false;
        root.clearSelection();
        root.results = [];
        root.page = 1;
        root.lastPage = 1;

        root.hasError = false;
        root.feedback = "Atualizando provedores...";

        providerProc.command = [
            "python3",
            root.scriptPath,
            "providers",
            "--purity",
            root.purity
        ];

        providerProc.running = true;
    }

    function changePurity(code) {
        if (root.busy || root.purity === code)
            return;

        root.purity = code;
        root.category = "111";

        root.refreshProviders();
    }

    function changeProvider(code) {
        if (root.busy || root.provider === code)
            return;

        if (root.providerIndex(code) === -1)
            return;

        root.provider = code;
        root.category = "111";

        root.search(true);
    }

    function search(resetPage) {
        if (root.busy || !root.providersLoaded)
            return;

        if (root.providerIndex(root.provider) === -1) {
            root.hasError = true;
            root.feedback = "Nenhum provedor disponível.";
            return;
        }

        if (resetPage)
            root.page = 1;

        root.clearSelection();
        root.hasError = false;
        root.feedback = "Pesquisando wallpapers...";

        searchProc.command = [
            "python3",
            root.scriptPath,
            "search",
            "--provider",
            root.provider,
            "--query",
            searchField.text,
            "--categories",
            root.category,
            "--sorting",
            root.sorting,
            "--resolutions",
            root.resolution,
            "--purity",
            root.purity,
            "--page",
            String(root.page)
        ];

        searchProc.running = true;
    }

    function applySelected() {
        if (root.busy || !root.selectedWallpaper)
            return;

        const item = root.selectedWallpaper;

        if (!item.url || !item.id || !item.provider)
            return;

        root.hasError = false;
        root.feedback = "Baixando wallpaper selecionado...";

        downloadProc.command = [
            "python3",
            root.scriptPath,
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
                        data.error || "Falha ao consultar provedores"
                    );
                }

                if (!Array.isArray(data.providers)) {
                    throw new Error(
                        "Lista de provedores inválida."
                    );
                }

                const validProviders = data.providers.filter(
                    function(item) {
                        return item &&
                            typeof item.code === "string" &&
                            typeof item.name === "string";
                    }
                );

                root.availableProviders = validProviders;
                root.providersLoaded = true;

                if (validProviders.length === 0) {
                    root.hasError = true;
                    root.feedback =
                        "Nenhum provedor disponível para este conteúdo.";
                    return;
                }

                // Preserve the selected provider whenever possible.
                if (root.providerIndex(root.provider) === -1) {
                    root.provider = validProviders[0].code;
                }

                root.hasError = false;
                root.feedback = "";

                // Run after providerProc has stopped.
                initialSearchTimer.restart();

            } catch (error) {
                root.availableProviders = [];
                root.providersLoaded = false;
                root.results = [];
                root.hasError = true;
                root.feedback =
                    "Erro ao carregar provedores: " + error.message;

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
                        data.error || "Falha na pesquisa"
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

            } catch (error) {
                root.results = [];
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
                        data.error || "Falha no download"
                    );
                }

                Wallpapers.apply(data.path);

                root.hasError = false;
                root.feedback =
                    "Wallpaper baixado e enviado para aplicação.";

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

        // Provider and search
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

        // Category, sorting and resolution
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

        // Content classification
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

        // Operation feedback
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

        // Wallpaper gallery
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

                        onTapped: {
                            root.selectWallpaper(
                                wallpaperDelegate.modelData
                            );
                        }
                    }
                }
            }
        }

        // Pagination and application
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
                enabled:
                    !root.busy &&
                    root.selectedWallpaper !== null

                materialIcon: downloadProc.running
                    ? "progress_activity"
                    : "wallpaper"

                mainText: downloadProc.running
                    ? "Aplicando..."
                    : "Aplicar"

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
