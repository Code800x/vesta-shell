
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentSubsection {
    id: root

    title: Translation.tr("Keyboard layout")
    tooltip: Translation.tr("Configure the keyboard layout used by Hyprland.")

    property string selectedLayout: "br"
    property string selectedVariant: "abnt2"
    property string feedback: ""

    property bool busy: false
    property bool initialized: false
    property bool lastOperationSucceeded: false

    readonly property string scriptPath:
        Qt.resolvedUrl("../../../scripts/keyboard/keyboard_config.py")
            .toString()
            .replace(/^file:\/\//, "")

    readonly property var layouts: [
        { name: "Português (Brasil)", code: "br" },
        { name: "English (US)", code: "us" },
        { name: "Português (Portugal)", code: "pt" },
        { name: "Español", code: "es" },
        { name: "English (UK)", code: "gb" },
        { name: "Deutsch", code: "de" },
        { name: "Français", code: "fr" },
        { name: "Italiano", code: "it" }
    ]

    readonly property var variants: ({
        "br": [
            { name: "Padrão", code: "" },
            { name: "ABNT2", code: "abnt2" },
            { name: "Sem teclas mortas", code: "nodeadkeys" }
        ],
        "us": [
            { name: "Padrão", code: "" },
            { name: "Internacional", code: "intl" },
            { name: "Internacional (AltGr)", code: "altgr-intl" }
        ],
        "pt": [
            { name: "Padrão", code: "" },
            { name: "Sem teclas mortas", code: "nodeadkeys" }
        ],
        "es": [
            { name: "Padrão", code: "" },
            { name: "Sem teclas mortas", code: "nodeadkeys" }
        ],
        "gb": [
            { name: "Padrão", code: "" },
            { name: "Internacional", code: "intl" }
        ],
        "de": [
            { name: "Padrão", code: "" },
            { name: "Sem teclas mortas", code: "nodeadkeys" }
        ],
        "fr": [
            { name: "Padrão", code: "" },
            { name: "Alternativo", code: "oss" }
        ],
        "it": [
            { name: "Padrão", code: "" }
        ]
    })

    function indexOfCode(items, code) {
        if (!items)
            return 0;

        for (let i = 0; i < items.length; ++i) {
            if (items[i].code === code)
                return i;
        }

        return 0;
    }

    function variantsForLayout() {
        return root.variants[root.selectedLayout] || [];
    }

    function parseResult(raw, isApply) {
        try {
            const result = JSON.parse(raw.trim());

            if (!result.ok) {
                root.lastOperationSucceeded = false;
                root.feedback = result.error || "Erro desconhecido";
                return;
            }

            if (!isApply) {
                root.selectedLayout = result.layout || "br";
                root.selectedVariant = result.variant || "";
                root.initialized = true;
                root.feedback = "";
            } else {
                root.lastOperationSucceeded = true;
                root.feedback = "Layout do teclado aplicado e salvo.";
            }
        } catch (error) {
            root.lastOperationSucceeded = false;
            root.feedback = "Não foi possível processar a resposta.";
            console.warn("[Vesta Keyboard]", error);
        }
    }

    Component.onCompleted: {
        statusProc.running = true;
    }

    Process {
        id: statusProc

        command: [
            "python3",
            root.scriptPath,
            "status"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                root.parseResult(text, false);
            }
        }
    }

    Process {
        id: applyProc

        command: [
            "python3",
            root.scriptPath,
            "apply",
            "--layout", root.selectedLayout,
            "--variant", root.selectedVariant,
            "--options", ""
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                root.parseResult(text, true);
            }
        }

        onRunningChanged: {
            root.busy = running;
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "Layout do teclado"
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: 13
                }

                StyledComboBox {
                    id: layoutSelector

                    Layout.fillWidth: true
                    buttonIcon: "keyboard"
                    textRole: "name"
                    model: root.layouts

                    currentIndex: root.indexOfCode(
                        root.layouts,
                        root.selectedLayout
                    )

                    onActivated: index => {
                        const item = root.layouts[index];

                        if (!item)
                            return;

                        root.selectedLayout = item.code;

                        const available = root.variantsForLayout();

                        root.selectedVariant =
                            root.selectedLayout === "br"
                                ? "abnt2"
                                : available[0].code;

                        root.feedback = "";
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "Variante"
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: 13
                }

                StyledComboBox {
                    id: variantSelector

                    Layout.fillWidth: true
                    buttonIcon: "tune"
                    textRole: "name"
                    model: root.variantsForLayout()

                    currentIndex: root.indexOfCode(
                        root.variantsForLayout(),
                        root.selectedVariant
                    )

                    onActivated: index => {
                        const available = root.variantsForLayout();
                        const item = available[index];

                        if (!item)
                            return;

                        root.selectedVariant = item.code;
                        root.feedback = "";
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButtonWithIcon {
                nerdIcon: "󰌌"

                mainText: root.busy
                    ? "Aplicando..."
                    : "Aplicar layout do teclado"

                enabled: !root.busy && root.initialized

                onClicked: {
                    root.feedback = "";
                    root.lastOperationSucceeded = false;
                    applyProc.running = true;
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.feedback
                wrapMode: Text.WordWrap
                font.pixelSize: 12

                color: root.lastOperationSucceeded
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colError

                visible: text.length > 0
            }
        }
    }
}
