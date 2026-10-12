import QtQuick
import Quickshell.Io

Item {
    id: root
    readonly property bool running: downloadProcess.running
    property string requestedId: ""
    signal lineReceived(string line)
    signal finished(int exitCode, string details)

    function start(command, imageId) {
        if (downloadProcess.running)
            return false;
        requestedId = String(imageId || "");
        downloadProcess.command = command;
        downloadProcess.running = true;
        return true;
    }

    function cancel() {
        if (downloadProcess.running)
            downloadProcess.running = false;
    }

    Process {
        id: downloadProcess
        running: false
        stdout: SplitParser {
            onRead: line => root.lineReceived(line)
        }
        stderr: StdioCollector { id: downloadErrors }
        onExited: (exitCode, exitStatus) => {
            root.finished(exitCode, downloadErrors.text.trim());
        }
    }
}
