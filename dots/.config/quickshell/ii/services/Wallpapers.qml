import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Provides a list of wallpapers and an "apply" action that calls the existing
 * switchwall.sh script. Pretty much a limited file browsing service.
 */
Singleton {
    id: root

    property string thumbgenScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/thumbgen-venv.sh`
    property string generateThumbnailsMagickScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/generate-thumbnails-magick.sh`
    property alias directory: folderModel.folder
    readonly property string effectiveDirectory: FileUtils.trimFileProtocol(folderModel.folder.toString())
    property url defaultFolder: Qt.resolvedUrl(`${Directories.pictures}/Wallpapers`)
    property alias folderModel: folderModel // Expose for direct binding when needed
    property string searchQuery: ""
    readonly property list<string> extensions: [ // TODO: add videos
        "jpg", "jpeg", "png", "webp", "avif", "bmp", "svg"
    ]
    property list<string> wallpapers: [] // List of absolute file paths (without file://)
    readonly property bool thumbnailGenerationRunning: thumbgenProc.running
    property real thumbnailGenerationProgress: 0

    signal changed()
    signal thumbnailGenerated(directory: string)
    signal thumbnailGeneratedFile(filePath: string)

    function load () {} // For forcing initialization
    
    function openFallbackPicker(darkMode = Appearance.m3colors.darkmode) {
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", darkMode ? "dark" : "light"]);
    }

    // The settings module selects an output; existing shortcuts keep applying to all.
    property string selectedOutput: ""
    readonly property var outputNames: HyprlandData.monitors.map(monitor => monitor.name)
    readonly property bool selectedOutputAvailable:
        outputNames.length > 0 && (!selectedOutput || outputNames.includes(selectedOutput))
    property var pendingApplications: []
    readonly property bool applying: applyProc.running || pendingApplications.length > 0
    property string lastApplyError: ""

    function captureTarget() {
        return { all: !selectedOutput,
            outputs: selectedOutput ? [selectedOutput] : outputNames.slice() };
    }

    function wallpaperForMonitor(name) {
        const background = Config.options.background;
        const configured = background.wallpaperByMonitor || {};
        const fallback = background.wallpaperDefault || {};
        return configured[name] || (fallback.path !== undefined ? fallback : {
            path: background.wallpaperPath || "",
            thumbnailPath: background.thumbnailPath || ""
        });
    }

    readonly property string themeSource: Config.options.background.wallpaperThemeSource || ""
    readonly property string themePath: Config.options.background.wallpaperThemePath || Config.options.background.wallpaperPath || ""
    property string lastThemeError: ""
    signal themeApplied()

    function themeEntryForSource(source) {
        return source ? wallpaperForMonitor(source) : {
            path: Config.options.background.wallpaperPath || "",
            thumbnailPath: Config.options.background.thumbnailPath || ""
        };
    }

    function applyThemeSource(source) {
        if (!themeEntryForSource(source).path) {
            lastThemeError = "Theme wallpaper file not found";
            return false;
        }
        const command = [Directories.wallpaperSwitchScriptPath, "--mode",
            Appearance.m3colors.darkmode ? "dark" : "light",
            "--theme-source", source || "auto"];
        pendingApplications = pendingApplications.concat([{command: command, themeOnly: true}]);
        lastThemeError = "";
        startNextApplication();
        return true;
    }

    function isActiveOnSelectedOutputs(path) {
        if (!path || !selectedOutputAvailable) return false;
        const target = captureTarget();
        const normalized = FileUtils.trimFileProtocol(path).replace(/\/+$/, "");
        return target.outputs.every(name =>
            FileUtils.trimFileProtocol(wallpaperForMonitor(name).path || "")
                .replace(/\/+$/, "") === normalized);
    }

    function applyToSelected(path, target = null) {
        return root.apply(path, Appearance.m3colors.darkmode, target || captureTarget());
    }

    function apply(path, darkMode = Appearance.m3colors.darkmode, target = null) {
        if (!path || path.length === 0) return false;
        const chosen = target || { all: true, outputs: outputNames.slice() };
        if (!chosen.outputs.length || chosen.outputs.some(name => !outputNames.includes(name))) {
            lastApplyError = "Selected monitor is no longer connected";
            return false;
        }
        const command = [Directories.wallpaperSwitchScriptPath, "--mode",
            darkMode ? "dark" : "light", "--image", path];
        chosen.outputs.forEach(name => command.push("--output", name));
        if (chosen.all) command.push("--all-outputs");
        pendingApplications = pendingApplications.concat([{command: command, themeOnly: false}]);
        lastApplyError = "";
        startNextApplication();
        return true;
    }

    function startNextApplication() {
        if (applyProc.running || pendingApplications.length === 0) return;
        const request = pendingApplications[0];
        pendingApplications = pendingApplications.slice(1);
        applyProc.themeOnly = request.themeOnly;
        applyProc.command = request.command;
        applyProc.running = true;
    }

    Process {
        id: applyProc
        property bool themeOnly: false
        stdout: StdioCollector { id: applyOutput }
        stderr: StdioCollector { id: applyErrors }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                if (applyProc.themeOnly) {
                    root.lastThemeError = "";
                    root.themeApplied();
                } else {
                    root.lastApplyError = "";
                    root.changed();
                }
            } else {
                const raw = applyErrors.text.trim() || applyOutput.text.trim();
                const lines = raw.split("\n");
                let message = applyProc.themeOnly ? "Theme application failed" : "Wallpaper application failed";
                try {
                    message = JSON.parse(lines[lines.length - 1]).error || message;
                } catch (error) {
                    console.warn("[Wallpapers]", raw);
                }
                if (applyProc.themeOnly) root.lastThemeError = message;
                else root.lastApplyError = message;
            }
            Qt.callLater(root.startNextApplication);
        }
    }

    // Restore only missing video players when monitors reconnect. The backend is
    // idempotent and serialized with wallpaper applications through its lock.
    Timer {
        id: restoreTimer
        interval: 500
        onTriggered: {
            if (root.applying || restoreProc.running) { restart(); return; }
            restoreProc.running = true;
        }
    }
    Connections {
        target: HyprlandData
        function onMonitorsChanged() { restoreTimer.restart(); }
    }
    Process {
        id: restoreProc
        command: ["python3", Quickshell.shellPath("scripts/wallpaper/output_manager.py"), "restore"]
        stderr: StdioCollector { id: restoreErrors }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) console.warn("[Wallpapers] Restore:", restoreErrors.text.trim());
        }
    }

    Process {
        id: selectProc
        property string filePath: ""
        property bool darkMode: Appearance.m3colors.darkmode
        function select(filePath, darkMode = Appearance.m3colors.darkmode) {
            selectProc.filePath = filePath
            selectProc.darkMode = darkMode
            selectProc.exec(["test", "-d", FileUtils.trimFileProtocol(filePath)])
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                setDirectory(selectProc.filePath);
                return;
            }
            root.apply(selectProc.filePath, selectProc.darkMode);
        }
    }

    function select(filePath, darkMode = Appearance.m3colors.darkmode) {
        selectProc.select(filePath, darkMode);
    }

    function randomFromCurrentFolder(darkMode = Appearance.m3colors.darkmode) {
        if (folderModel.count === 0) return;
        const randomIndex = Math.floor(Math.random() * folderModel.count);
        const filePath = folderModel.get(randomIndex, "filePath");
        print("Randomly selected wallpaper:", filePath);
        root.select(filePath, darkMode);
    }

    Process {
        id: validateDirProc
        property string nicePath: ""
        function setDirectoryIfValid(path) {
            validateDirProc.nicePath = FileUtils.trimFileProtocol(path).replace(/\/+$/, "")
            if (/^\/*$/.test(validateDirProc.nicePath)) validateDirProc.nicePath = "/";
            validateDirProc.exec([
                "bash", "-c",
                `if [ -d "${validateDirProc.nicePath}" ]; then echo dir; elif [ -f "${validateDirProc.nicePath}" ]; then echo file; else echo invalid; fi`
            ])
        }
        stdout: StdioCollector {
            onStreamFinished: {
                    root.directory = Qt.resolvedUrl(validateDirProc.nicePath)
                const result = text.trim()
                if (result === "dir") {
                } else if (result === "file") {
                    root.directory = Qt.resolvedUrl(FileUtils.parentDirectory(validateDirProc.nicePath))
                } else {
                    // Ignore
                }
            }
        }
    }
    function setDirectory(path) {
        validateDirProc.setDirectoryIfValid(path)
    }
    function navigateUp() {
        folderModel.navigateUp()
    }
    function navigateBack() {
        folderModel.navigateBack()
    }
    function navigateForward() {
        folderModel.navigateForward()
    }

    // Folder model
    FolderListModelWithHistory {
        id: folderModel
        folder: Qt.resolvedUrl(root.defaultFolder)
        caseSensitive: false
        nameFilters: root.extensions.map(ext => `*${searchQuery.split(" ").filter(s => s.length > 0).map(s => `*${s}*`)}*.${ext}`)
        showDirs: true
        showDotAndDotDot: false
        showOnlyReadable: true
        sortField: FolderListModel.Time
        sortReversed: false
        onCountChanged: {
            root.wallpapers = []
            for (let i = 0; i < folderModel.count; i++) {
                const path = folderModel.get(i, "filePath") || FileUtils.trimFileProtocol(folderModel.get(i, "fileURL"))
                if (path && path.length) root.wallpapers.push(path)
            }
        }
    }

    // Thumbnail generation
    function generateThumbnail(size: string) {
        if (!["normal", "large", "x-large", "xx-large"].includes(size)) throw new Error("Invalid thumbnail size");
        thumbgenProc.directory = root.directory
        thumbgenProc.running = false
        thumbgenProc.command = [
            "bash", "-c",
            `${thumbgenScriptPath} --size ${size} --machine_progress -d ${FileUtils.trimFileProtocol(root.directory)} || ${generateThumbnailsMagickScriptPath} --size ${size} -d ${FileUtils.trimFileProtocol(root.directory)}`,
        ]
        // console.log("[Wallpapers] Updating thumbnails with command ", thumbgenProc.command.join(" "))
        root.thumbnailGenerationProgress = 0
        thumbgenProc.running = true
    }
    Process {
        id: thumbgenProc
        property string directory
        stdout: SplitParser {
            onRead: data => {
                // print("thumb gen proc:", data)
                let match = data.match(/PROGRESS (\d+)\/(\d+)/)
                if (match) {
                    const completed = parseInt(match[1])
                    const total = parseInt(match[2])
                    root.thumbnailGenerationProgress = completed / total
                }
                match = data.match(/FILE (.+)/)
                if (match) {
                    const filePath = match[1]
                    root.thumbnailGeneratedFile(filePath)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // print("[Wallpapers] Thumbnail generation completed with exit code", exitCode)
            root.thumbnailGenerated(thumbgenProc.directory)
        }
    }

    IpcHandler {
        target: "wallpapers"

        function apply(path: string): void {
            root.apply(path);
        }
    }
}
