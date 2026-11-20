import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// The vault passwords, on their own tab. A password can unlock several wallets, as each wallet's
// rule says; its name shows when you unlock. Create, rename, change or remove them here.
ColumnLayout {
    id: view
    objectName: "passwordsView"
    property var backend
    spacing: 10

    function parse(raw, empty) {
        try { return JSON.parse(raw) } catch (e) { return empty }
    }
    readonly property var settings: parse(backend ? backend.walletsJson : "{}", ({}))
    readonly property var passwords: settings.passwords || []

    // Content is capped and centred at 560, matching the Wallets tab.
    readonly property int contentWidth: 560

    LogosText {
        objectName: "passwordError"
        visible: !!(view.backend && view.backend.walletError)
        Layout.fillWidth: true
        Layout.maximumWidth: view.contentWidth
        Layout.alignment: Qt.AlignHCenter
        text: (view.backend && view.backend.walletError) || ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.palette.error
    }

    ScrollView {
        id: passwordScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: Math.min(passwordScroll.availableWidth, view.contentWidth)
            x: Math.max(0, (passwordScroll.availableWidth - width) / 2)
            spacing: 10

            // No "Passwords" heading: the tab already names it. Keep the explanation.
            LogosText {
                Layout.fillWidth: true
                text: "A password can unlock several wallets, as each wallet's rule says. Its name shows when you unlock."
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.palette.textSecondary
            }
            LogosText {
                visible: view.passwords.length === 0
                Layout.fillWidth: true
                text: "No passwords yet. Add one below, then set it as a wallet's unlock rule."
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            Repeater {
                model: view.passwords
                delegate: Rectangle {
                    id: pwRow
                    objectName: "passwordRow"
                    Layout.fillWidth: true
                    radius: 6
                    color: Theme.palette.backgroundMuted
                    border.color: Theme.palette.border
                    border.width: 1
                    implicitHeight: pwBody.implicitHeight + 2 * Theme.spacing.medium
                    property string mode: ""

                    ColumnLayout {
                        id: pwBody
                        anchors.fill: parent
                        anchors.margins: Theme.spacing.medium
                        spacing: Theme.spacing.small

                        // Title (the password's name) + a secondary line (what it unlocks), like a wallet card.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.small
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                LogosText {
                                    objectName: "passwordName"
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    font.weight: Theme.typography.weightBold
                                    font.pixelSize: Theme.typography.subtitleText
                                }
                                LogosText {
                                    Layout.fillWidth: true
                                    text: modelData.wallets.length === 0
                                          ? "Not a wallet's unlock rule yet"
                                          : "Unlocks " + modelData.wallets.length + " wallet" + (modelData.wallets.length === 1 ? "" : "s")
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                    color: Theme.palette.textSecondary
                                    font.pixelSize: Theme.typography.secondaryText
                                }
                            }
                            LogosButton { text: "Rename"; onClicked: pwRow.mode = pwRow.mode === "rename" ? "" : "rename" }
                            LogosButton { text: "Change"; onClicked: pwRow.mode = pwRow.mode === "change" ? "" : "change" }
                            LogosButton {
                                objectName: "passwordRemove"
                                enabled: modelData.wallets.length === 0
                                text: "Remove"
                                onClicked: view.backend.removePassword(modelData.id)
                            }
                        }
                        RowLayout {
                            visible: pwRow.mode === "rename"
                            Layout.fillWidth: true
                            LogosTextField { id: renameField; Layout.fillWidth: true; text: modelData.name }
                            LogosButton {
                                text: "Save"
                                enabled: renameField.text.trim().length > 0
                                onClicked: { view.backend.renamePassword(modelData.id, renameField.text); pwRow.mode = "" }
                            }
                        }
                        ColumnLayout {
                            visible: pwRow.mode === "change"
                            Layout.fillWidth: true
                            LogosTextField {
                                id: oldPw; objectName: "passwordOld"; Layout.fillWidth: true
                                echoMode: TextInput.Password; placeholderText: "Current password"
                                Component.onCompleted: textInput.passwordMaskDelay = 0
                            }
                            LogosTextField {
                                id: newPw; objectName: "passwordNew"; Layout.fillWidth: true
                                echoMode: TextInput.Password; placeholderText: "New password, 8 characters or more"
                                Component.onCompleted: textInput.passwordMaskDelay = 0
                            }
                            LogosTextField {
                                id: newPw2; Layout.fillWidth: true
                                echoMode: TextInput.Password; placeholderText: "New password again"
                                Component.onCompleted: textInput.passwordMaskDelay = 0
                            }
                            LogosButton {
                                objectName: "passwordChangeSave"
                                enabled: oldPw.text.length > 0 && newPw.text.length >= 8 && newPw.text === newPw2.text
                                text: "Change it"
                                onClicked: {
                                    view.backend.changePassword(modelData.id, oldPw.text, newPw.text)
                                    oldPw.text = ""; newPw.text = ""; newPw2.text = ""
                                    pwRow.mode = ""
                                }
                            }
                        }
                    }
                }
            }

            // ── add a password ──────────────────────────────────────────────
            LogosText {
                Layout.topMargin: 8
                text: "Add a password"
                textFormat: Text.PlainText
                font.bold: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                LogosTextField {
                    id: addName; objectName: "passwordAddName"; Layout.fillWidth: true
                    placeholderText: "New password's name (e.g. Home)"
                }
                LogosTextField {
                    id: addPw; objectName: "passwordAddField"; Layout.fillWidth: true
                    echoMode: TextInput.Password; placeholderText: "Password, 8 characters or more"
                    Component.onCompleted: textInput.passwordMaskDelay = 0
                }
                LogosTextField {
                    id: addPw2; Layout.fillWidth: true
                    echoMode: TextInput.Password; placeholderText: "Password again"
                    Component.onCompleted: textInput.passwordMaskDelay = 0
                }
                LogosButton {
                    objectName: "passwordAdd"
                    enabled: addName.text.trim().length > 0 && addPw.text.length >= 8 && addPw.text === addPw2.text
                    text: "Add password"
                    onClicked: {
                        view.backend.createPassword(addName.text, addPw.text)
                        addName.text = ""; addPw.text = ""; addPw2.text = ""
                    }
                }
            }
        }
    }
}
