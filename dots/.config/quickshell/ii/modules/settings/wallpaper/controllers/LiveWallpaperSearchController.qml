import QtQuick
import Quickshell.Io
import "../utils/WallpaperResponses.js" as WallpaperResponses

Item {
    id: controller
    readonly property bool running: searchProc.running
    property int requestedPage: 1

    signal completed(var items, int page, int lastPage)
    signal failed(string message, string details)

    function start(command, page) {
        if (searchProc.running)
            return;
        requestedPage = Math.max(1, Math.min(100, Number(page) || 1));
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
                // Mantém a paginação e os itens originais dos provedores live.
                const items = data.items || [];
                const page = Math.max(
                    1, Number(data.page) || controller.requestedPage
                );
                const lastPage = Math.max(
                    page, Math.min(100, Number(data.last_page) || page)
                );
                controller.completed(items, page, lastPage);
            } catch (error) {
                controller.failed(error.message, searchErrors.text.trim());
            }
        }
    }
}
