import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// The signing approval surface.
//
// This view renders the keystore's own lines VERBATIM and collects the vault
// password. It never parses an intent — it has no client for any wallet module
// and could not decode one. Every line on screen came from the signer that will
// produce the signature.
//
// Rendering rule: every text item in the request region sets
// `textFormat: Text.PlainText` explicitly. LogosText is a bare Text with no
// textFormat, i.e. Qt's AutoText HTML autodetection, so a line containing
// markup would otherwise render as markup. Nothing here elides or reformats.
Item {
    id: root
    anchors.fill: parent

    readonly property var backend: logos.module("signer_ui")
    readonly property bool ready: backend !== null && logos.isViewModuleReady("signer_ui")
    readonly property var queue: {
        try { return JSON.parse(backend ? backend.pendingJson : "[]") } catch (e) { return [] }
    }
    readonly property bool showing: ready && backend.renderedHandle !== ""

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            LogosText {
                text: root.ready ? backend.statusText : "Connecting…"
                textFormat: Text.PlainText
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                text: "Refresh"
                enabled: root.ready
                onClicked: backend.refresh()
            }
        }

        LogosText {
            visible: root.ready && backend.lastError !== ""
            Layout.fillWidth: true
            text: root.ready ? backend.lastError : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Logos.Theme.danger !== undefined ? Logos.Theme.danger : "#c0392b"
        }

        // ── the queue ───────────────────────────────────────────────────────
        LogosText {
            visible: !root.showing
            text: root.queue.length === 0
                  ? "No signing requests are waiting."
                  : "Select a request to review:"
            textFormat: Text.PlainText
        }

        ListView {
            visible: !root.showing
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.queue
            delegate: LogosButton {
                width: ListView.view.width
                // Summary only — the queue never carries leg detail.
                text: (modelData.requester || "unknown") + " — " +
                      (modelData.purpose || "signature") + "  [" +
                      String(modelData.handle).substring(0, 12) + "]"
                onClicked: backend.acknowledge(modelData.handle)
            }
        }

        // ── the request under review ────────────────────────────────────────
        ColumnLayout {
            visible: root.showing
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            LogosText {
                Layout.fillWidth: true
                text: "Requested by: " + (root.ready ? backend.renderedRequester : "")
                textFormat: Text.PlainText
                font.bold: true
            }

            // The keystore's lines, one per row, unmodified.
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: root.ready ? backend.renderLines : []
                        delegate: LogosText {
                            Layout.fillWidth: true
                            text: modelData
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            font.family: "monospace"
                        }
                    }
                }
            }

            LogosTextField {
                id: pw
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "Vault password"

                // Mask every character immediately. Qt's default reveals the
                // last character typed for a second, which is exactly the
                // character an onlooker needs. `passwordMaskDelay` lives on the
                // inner TextInput -- LogosTextField does not re-expose it, but
                // it does expose the input itself as a readonly alias, so set
                // it there. Assigning it on the control fails to compile with
                // "Cannot assign to non-existent property", which takes the
                // WHOLE view down: a QML compile error means the plugin never
                // renders at all.
                Component.onCompleted: textInput.passwordMaskDelay = 0
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                LogosButton {
                    text: "Reject"
                    onClicked: { backend.reject(backend.renderedHandle); pw.text = "" }
                }
                LogosButton {
                    text: "Back"
                    onClicked: { backend.dismiss(); pw.text = "" }
                }
                Item { Layout.fillWidth: true }
                LogosButton {
                    id: approveBtn
                    // The dwell flag is owned by C++, so editing this binding
                    // cannot shorten it; the backend refuses early approvals
                    // regardless of what the view believes.
                    enabled: root.ready && backend.dwellElapsed && pw.text.length > 0
                    text: backend.dwellElapsed ? "Approve" : "Reading…"
                    onClicked: {
                        backend.approve(backend.renderedHandle, backend.renderedBundleId, pw.text)
                        pw.text = ""
                    }
                }
            }
        }
    }
}
