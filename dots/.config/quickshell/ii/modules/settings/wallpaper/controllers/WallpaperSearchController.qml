import QtQuick
import Quickshell.Io
import "../utils/WallpaperResponses.js" as WallpaperResponses

Item {
    id: controller
    readonly property bool running: searchProc.running
    signal completed(var items, int lastPage)
    signal failed(string message, string details)

    function start(command) {
        if (searchProc.running)
            return;
        searchProc.command = command;
        searchProc.running = true;
    }

    Process {
        id: searchProc
        running: false
        stdout: StdioCollector { id: searchOutput }
        stderr: StdioCollector { id: searchErrors }
        onExited: (exitCode, exitStatus) => {
            try {
                const data = WallpaperResponses.parseResponse(
                    searchOutput.text, exitCode, "Falha na pesquisa.",
                    searchErrors.text
                );
                const items = WallpaperResponses.uniqueWallpapers(data.items);
                const lastPage = Math.max(1, Number(data.last_page) || 1);
                controller.completed(items, lastPage);
            } catch (error) {
                controller.failed(error.message, searchErrors.text.trim());
            }
        }
    }
}
