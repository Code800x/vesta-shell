import QtQuick
import Quickshell.Io
import "../utils/WallpaperResponses.js" as WallpaperResponses

Item {
    id: root
    readonly property bool running: batchProcess.running
    signal completed(var paths, string provider, string ids)
    signal failed(string message, string details, string provider, string ids)

    function start(scriptPath, provider, ids) {
        if (batchProcess.running)
            return;
        const cleanIds = ids.map(id => String(id)).filter(id => id.length > 0);
        batchProcess.requestedProvider = provider;
        batchProcess.requestedIds = cleanIds.join(",");
        batchProcess.command = [
            "python3", scriptPath, "status-batch",
            "--provider", provider, "--image-ids"
        ].concat(cleanIds);
        batchProcess.running = true;
    }

    Process {
        id: batchProcess
        running: false
        property string requestedProvider: ""
        property string requestedIds: ""
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: (exitCode, exitStatus) => {
            try {
                const data = WallpaperResponses.parseResponse(
                    output.text, exitCode, "Falha na consulta de cache."
                );
                const paths = {};
                const items = data.items || {};
                for (const id of Object.keys(items)) {
                    if (items[id] && items[id].cached && items[id].path)
                        paths[id] = String(items[id].path);
                }
                root.completed(paths, requestedProvider, requestedIds);
            } catch (error) {
                root.failed(
                    error.message, errors.text.trim(),
                    requestedProvider, requestedIds
                );
            }
        }
    }
}
