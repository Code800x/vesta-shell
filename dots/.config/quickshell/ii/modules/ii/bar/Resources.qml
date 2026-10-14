import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool alwaysShowAllResources: false
    implicitWidth: (Config.options.bar.resources.showMemory || Config.options.bar.resources.showSwap || Config.options.bar.resources.showCpu)
        ? rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin : 0
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    RowLayout {
        id: rowLayout

        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        Resource {
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            displayText: ResourceUsage.kbToGbString(ResourceUsage.memoryUsed)
            shown: Config.options.bar.resources.showMemory
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold
        }

        Resource {
            iconName: "swap_horiz"
            percentage: ResourceUsage.swapUsedPercentage
            displayText: ResourceUsage.kbToGbString(ResourceUsage.swapUsed)
            shown: Config.options.bar.resources.showSwap
            Layout.leftMargin: shown && Config.options.bar.resources.showMemory ? 6 : 0
            warningThreshold: Config.options.bar.resources.swapWarningThreshold
        }

        Resource {
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            displayText: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
            shown: Config.options.bar.resources.showCpu
            Layout.leftMargin: shown && (Config.options.bar.resources.showMemory || Config.options.bar.resources.showSwap) ? 6 : 0
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold
        }

    }

    ResourcesPopup {
        hoverTarget: root
    }
}
