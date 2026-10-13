pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: panelRoot
        required property var modelData

        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        readonly property var monitorWallpaper: Wallpapers.wallpaperForMonitor(modelData.name)
        readonly property bool wallpaperIsVideo: /\.(mp4|webm|mkv|avi|mov)$/i.test(monitorWallpaper.path || "")
        WlrLayershell.layer: wallpaperIsVideo ? WlrLayer.Background : WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        StyledImage {
            anchors.fill: parent
            source: panelRoot.wallpaperIsVideo ? "" : (panelRoot.monitorWallpaper.path || "")
            fillMode: Image.PreserveAspectCrop
        }
    }
}
