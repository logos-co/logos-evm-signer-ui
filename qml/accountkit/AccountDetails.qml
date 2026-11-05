import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "roster.js" as Roster

// One account on a wallet card: its name and number, script type, derivation path and address
// (a Bitcoin account's first receiving one), with the app's own actions for it.
Item {
    id: row
    property var entry: null
    property string namePrefix: ""
    // Labels, or { id, label, enabled, tip }; or a function of the entry that returns them.
    property var actions: []
    signal action(string id, var entry)
    signal copied(string value)

    readonly property var shown: Roster.actions(actions, entry)
    readonly property string address: Roster.rowAddress(entry)
    implicitHeight: layout.implicitHeight
    implicitWidth: 480

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                LogosText {
                    objectName: row.namePrefix + "Name"
                    // Shrinks before the number and badges do, and never past its own text.
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.maximumWidth: implicitWidth
                    text: Roster.rowTitle(row.entry)
                    textFormat: Text.PlainText
                    font.bold: true
                    elide: Text.ElideRight
                }
                RowLayout {
                    spacing: 8
                    LogosText {
                        objectName: row.namePrefix + "Id"
                        visible: text.length > 0
                        text: Roster.rowId(row.entry)
                        textFormat: Text.PlainText
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    Repeater {
                        model: Roster.badges(row.entry)
                        delegate: LogosBadge {
                            required property string modelData
                            required property int index
                            objectName: row.namePrefix + "Badge_" + index
                            text: modelData
                            color: Theme.palette.textSecondary
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                LogosText {
                    text: "Derivation path"
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosText {
                    objectName: row.namePrefix + "Path"
                    text: Roster.text(row.entry && row.entry.path) || "Unavailable"
                    textFormat: Text.PlainText
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                }
                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                LogosText {
                    objectName: row.namePrefix + "AddressLabel"
                    text: Roster.addressLabel(row.entry)
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosText {
                    objectName: row.namePrefix + "Address"
                    text: Roster.rowAddressText(row.entry)
                    textFormat: Text.PlainText
                    color: row.address ? Theme.palette.text : Theme.palette.textSecondary
                    font.family: row.address ? Theme.typography.mono : Theme.typography.publicSans
                    font.pixelSize: Theme.typography.secondaryText
                    // Already shortened in the middle: trimming it again would match thousands.
                    elide: Text.ElideNone
                }
                LogosCopyButton {
                    objectName: row.namePrefix + "Copy"
                    visible: row.address.length > 0
                    value: row.address
                    Accessible.name: "Copy address"
                    ToolTip.text: "Copy address"
                    ToolTip.visible: hovered
                    ToolTip.delay: 400
                    onCopied: function (v) { row.copied(v) }
                }
                Item { Layout.fillWidth: true }
            }
        }

        Repeater {
            model: row.shown
            delegate: LogosButton {
                required property var modelData
                objectName: row.namePrefix + "Action_" + Roster.actionName(modelData)
                text: modelData.label
                compact: true
                enabled: modelData.enabled
                ToolTip.text: modelData.tip
                ToolTip.visible: hovered && modelData.tip.length > 0
                ToolTip.delay: 400
                onClicked: row.action(modelData.id, row.entry)
            }
        }
    }
}
