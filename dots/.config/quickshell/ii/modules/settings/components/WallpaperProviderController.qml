import QtQuick
import Quickshell.Io
import "WallpaperResponses.js" as WallpaperResponses

Item {
    id: controller
    property bool running: providerProc.running
    signal completed(var providers)
    signal failed(string message, string details)

    function start(command) {
        if (providerProc.running)
            return;
        providerProc.command = command;
        providerProc.running = true;
    }

    Process {
        id: providerProc
        running: false
        stdout: StdioCollector { id: providerOutput }
        stderr: StdioCollector { id: providerErrors }
        onExited: (exitCode, exitStatus) => {
            try {
                const data = WallpaperResponses.parseResponse(
                    providerOutput.text, exitCode, "Falha ao consultar provedores."
                );
                if (!Array.isArray(data.providers))
                    throw new Error("Lista de provedores inválida.");
                const providers = WallpaperResponses.validProviders(data.providers);
                controller.completed(providers);
            } catch (error) {
                controller.failed(error.message, providerErrors.text.trim());
            }
        }
    }
}
