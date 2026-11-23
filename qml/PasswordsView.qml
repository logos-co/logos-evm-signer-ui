import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// The vault passwords, on their own tab. A password can unlock several wallets, as each wallet's
// rule says; its name shows when you unlock. Add, rename, change or remove them in a sheet, the
// same way the Keycard app edits a wallet: a pencil by the name renames, a pencil and a trash on
// the right change and remove.
ColumnLayout {
    id: view
    objectName: "passwordsView"
    property var backend
    // The host opens the add/rename/change/remove sheet.
    signal addPassword()
    signal renamePassword(string id, string name)
    signal changePassword(string id, string name)
    signal removePassword(string id, string name, int wallets)
    spacing: 10

    readonly property url pencilIcon: Qt.resolvedUrl("assets/edit.svg")
    readonly property url trashIcon: Qt.resolvedUrl("assets/delete.svg")

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

    // The add action sits on top of the list, full column width. The empty state offers its own
    // button instead, so this one is only shown once there are passwords.
    LogosButton {
        objectName: "passwordAddTop"
        visible: view.passwords.length > 0
        Layout.fillWidth: true
        Layout.maximumWidth: view.contentWidth
        Layout.alignment: Qt.AlignHCenter
        variant: LogosButton.Variant.Primary
        text: "Add password"
        onClicked: view.addPassword()
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

            // Empty state, matching the Keycard app: a centred block with a small Add button.
            EmptyState {
                visible: view.passwords.length === 0
                Layout.fillWidth: true
                title: "No passwords yet"
                subtitle: "A password can unlock several wallets, as each wallet's rule says. Add one, then set it as a wallet's unlock rule."
                actionText: "Add password"
                onAction: view.addPassword()
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

                    RowLayout {
                        id: pwBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.spacing.medium
                        spacing: Theme.spacing.small

                        // Name + a secondary line (what it unlocks), with the rename pencil beside the name.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing.tiny
                                LogosText {
                                    objectName: "passwordName"
                                    // Hug the name so the pencil sits right after it; cap the width
                                    // so a very long name elides instead of pushing the pencil away.
                                    Layout.maximumWidth: 360
                                    text: modelData.name
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    font.weight: Theme.typography.weightBold
                                    font.pixelSize: Theme.typography.subtitleText
                                }
                                LogosIconButton {
                                    objectName: "passwordRename"
                                    Accessible.name: "Rename password"
                                    flat: true; size: 28; iconSize: 16
                                    iconSource: view.pencilIcon
                                    iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
                                    onClicked: view.renamePassword(modelData.id, modelData.name)
                                    LogosToolTip { text: "Rename"; visible: parent.hovered; delay: 400 }
                                }
                                // Absorbs the rest of the row so the pencil stays beside the name.
                                Item { Layout.fillWidth: true }
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

                        // Change (pencil) then remove (trash), on the same line, matching the Keycard card.
                        LogosIconButton {
                            objectName: "passwordChange"
                            Accessible.name: "Change password"
                            flat: true; size: 28; iconSize: 16
                            iconSource: view.pencilIcon
                            iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
                            onClicked: view.changePassword(modelData.id, modelData.name)
                            LogosToolTip { text: "Change password"; visible: parent.hovered; delay: 400 }
                        }
                        LogosIconButton {
                            objectName: "passwordRemove"
                            Accessible.name: "Remove password"
                            flat: true; size: 28; iconSize: 16
                            iconSource: view.trashIcon
                            iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
                            // Always opens the sheet: when the password unlocks wallets, the sheet
                            // explains why it can't be removed yet instead of failing silently.
                            onClicked: view.removePassword(modelData.id, modelData.name, modelData.wallets.length)
                            LogosToolTip { text: "Remove"; visible: parent.hovered; delay: 400 }
                        }
                    }
                }
            }
        }
    }
}
