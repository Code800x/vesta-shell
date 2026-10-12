
import QtQuick
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

        buttonRadius: Appearance.rounding.small
        materialIcon: "search"
        mainText: "Pesquisar"

        onClicked: root.searchRequested()
    }

    RippleButtonWithIcon {
        Layout.preferredHeight: 48

        enabled: root.canSearch && root.hasQuery

        buttonRadius: Appearance.rounding.small
        materialIcon: "close"
        mainText: "Limpar"

        onClicked: root.clearRequested()
    }
}
