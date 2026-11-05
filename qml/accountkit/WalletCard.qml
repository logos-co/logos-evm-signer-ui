import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "roster.js" as Roster

// One wallet, as the Signer, Keycard and Keys apps show it: its name and Wallet ID (the master
// fingerprint), the app's lines and strips, then one row per account. Each app brings its own
// actions: beside the title, in a strip, on each row, and at the bottom.
Frame {
    id: card
    property string namePrefix: ""
    property string title: ""
    property string fingerprint: ""
    // Beside the actions at the top, as "Unlocked".
    property string stateText: ""
    // Who holds it, or how it unlocks.
    property var lines: []
    // A device in use, a phrase kept here, a warning: [{ id, text, warn, actions }].
    property var strips: []
    property bool locked: false
    property string lockedText: "Locked · its ID and accounts show once you unlock it in the Signer app."
    property string emptyText: "No accounts yet."
    // Entries as the roster gives them, plus `firstAddress` for Bitcoin; shown in a fixed order.
    property var accounts: []
    // Labels, or { id, label, enabled, tip }. accountActions may be a function of the entry.
    property var actions: []
    property var lockedActions: []
    property var accountActions: []
    property var leftActions: []
    property var rightActions: []
    // The app's own items, as an inline editor, go above the bottom actions.
    default property alias content: extraArea.data

    signal action(string id)
    signal stripAction(int index, string id)
    signal accountAction(string id, var entry)
    signal copied(string value)

    readonly property var rows: Roster.sortAccounts(accounts)
    readonly property var bottomLeft: Roster.actions(leftActions)
    readonly property var bottomRight: Roster.actions(rightActions)

    objectName: namePrefix + "Card"
    padding: Theme.spacing.medium
    background: Rectangle {
        radius: 6
        color: Theme.palette.backgroundMuted
        border.color: Theme.palette.border
        border.width: 1
    }

    component ActionButton: LogosButton {
        required property var spec
        property string prefix: card.namePrefix
        objectName: prefix + "Action_" + Roster.actionName(spec)
        text: spec.label
        enabled: spec.enabled
        ToolTip.text: spec.tip
        ToolTip.visible: hovered && spec.tip.length > 0
        ToolTip.delay: 400
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 4
                LogosText {
                    objectName: card.namePrefix + "Title"
                    Layout.fillWidth: true
                    text: card.title
                    textFormat: Text.PlainText
                    font.bold: true
                    font.pixelSize: Theme.typography.subtitleText
                    elide: Text.ElideRight
                }
                RowLayout {
                    visible: card.fingerprint.length > 0 && !card.locked
                    spacing: 8
                    LogosText {
                        text: "Wallet ID"
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosText {
                        objectName: card.namePrefix + "WalletId"
                        text: card.fingerprint
                        textFormat: Text.PlainText
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosText {
                        text: "master fingerprint"
                        color: Theme.palette.textTertiary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                }
                Repeater {
                    model: card.lines
                    delegate: LogosText {
                        required property var modelData
                        required property int index
                        objectName: card.namePrefix + "Line_" + index
                        Layout.fillWidth: true
                        text: Roster.text(modelData)
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                }
            }
            LogosText {
                objectName: card.namePrefix + "State"
                visible: text.length > 0
                Layout.alignment: Qt.AlignTop
                text: card.stateText
                textFormat: Text.PlainText
            }
            Repeater {
                model: Roster.actions(card.actions)
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    Layout.alignment: Qt.AlignTop
                    onClicked: card.action(spec.id)
                }
            }
        }

        Repeater {
            model: card.strips
            delegate: Rectangle {
                id: strip
                required property var modelData
                required property int index
                // Named by its id when it has one, so a strip's name doesn't shift with the others.
                readonly property string key: Roster.text(modelData && modelData.id) || String(index)
                readonly property string prefix: card.namePrefix + "Strip_" + key + "_"
                objectName: card.namePrefix + "Strip_" + key
                Layout.fillWidth: true
                implicitHeight: stripRow.implicitHeight + 2 * Theme.spacing.small
                radius: 6
                color: Theme.palette.backgroundSecondary
                RowLayout {
                    id: stripRow
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing.medium
                    anchors.rightMargin: Theme.spacing.small
                    spacing: Theme.spacing.small
                    LogosText {
                        objectName: strip.prefix + "Text"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: Roster.text(strip.modelData && strip.modelData.text)
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: strip.modelData && strip.modelData.warn ? Theme.palette.error : Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    Repeater {
                        model: Roster.actions(strip.modelData && strip.modelData.actions)
                        delegate: ActionButton {
                            required property var modelData
                            spec: modelData
                            prefix: strip.prefix
                            onClicked: card.stripAction(strip.index, spec.id)
                        }
                    }
                }
            }
        }

        RowLayout {
            visible: card.locked
            Layout.fillWidth: true
            LogosText {
                objectName: card.namePrefix + "Locked"
                Layout.fillWidth: true
                text: card.lockedText
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
            }
            Repeater {
                model: Roster.actions(card.lockedActions)
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    onClicked: card.action(spec.id)
                }
            }
        }

        LogosText {
            objectName: card.namePrefix + "Empty"
            visible: !card.locked && card.rows.length === 0
            text: card.emptyText
            color: Theme.palette.textSecondary
        }

        ColumnLayout {
            visible: !card.locked && card.rows.length > 0
            Layout.fillWidth: true
            spacing: 0
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.palette.borderSubtle }
            Repeater {
                model: card.rows
                delegate: ColumnLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0
                    AccountDetails {
                        objectName: card.namePrefix + "Account_" + index
                        namePrefix: card.namePrefix + "Account_" + index + "_"
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.small
                        Layout.bottomMargin: Theme.spacing.small
                        entry: modelData
                        actions: card.accountActions
                        onAction: function (id, entry) { card.accountAction(id, entry) }
                        onCopied: function (v) { card.copied(v) }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.palette.borderSubtle }
                }
            }
        }

        ColumnLayout {
            id: extraArea
            objectName: card.namePrefix + "Content"
            Layout.fillWidth: true
            spacing: Theme.spacing.small
        }

        RowLayout {
            visible: card.bottomLeft.length + card.bottomRight.length > 0
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            Repeater {
                model: card.bottomLeft
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    onClicked: card.action(spec.id)
                }
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: card.bottomRight
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    onClicked: card.action(spec.id)
                }
            }
        }
    }
}
