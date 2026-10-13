import "../../utils/SettingsMessages.js" as SettingsMessages
import QtQuick
import qs.services
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: root
    spacing: 8
    property bool canSearch: true
    property bool hasQuery: false
    signal searchRequested()
    signal clearRequested()

    RippleButtonWithIcon {
        Layout.preferredHeight: 48
        enabled: root.canSearch
        materialIcon: "search"
        mainText: Translation.tr("Search")
        buttonRadius: Appearance.rounding.small
        onClicked: root.searchRequested()
    }
    RippleButtonWithIcon {
        Layout.preferredHeight: 48
        enabled: root.canSearch && root.hasQuery
        materialIcon: "close"
        mainText: Translation.tr("Clear")
        buttonRadius: Appearance.rounding.small
        onClicked: root.clearRequested()
    }
}
