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
    // Icons for the inline edit (rename) by the name and the trash (remove) at the far right.
    property url editIcon: ""
    property url trashIcon: ""
    signal action(string id, var entry)
    signal copied(string value)

    readonly property var shown: Roster.actions(actions, entry)
    readonly property var editAction: shown.filter(function (a) { return a.id === "rename" })[0] || null
    readonly property var removeAction: shown.filter(function (a) { return a.id === "remove" })[0] || null
    readonly property var otherActs: shown.filter(function (a) { return ["rename", "remove"].indexOf(a.id) < 0 })
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
                    // Shrinks before the number and badges do, and never past its own text. Rounded
                    // up: the layout snaps to whole pixels, and a fraction short elides it.
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.maximumWidth: Math.ceil(implicitWidth)
                    text: Roster.rowTitle(row.entry)
                    textFormat: Text.PlainText
                    font.bold: true
                    elide: Text.ElideRight
                }
                LogosIconButton {
                    objectName: row.namePrefix + "Edit"
                    visible: !!row.editAction
                    enabled: !row.editAction || row.editAction.enabled !== false
                    flat: true; size: 24; iconSize: 13
                    iconSource: row.editIcon
                    iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
                    onClicked: if (row.editAction) row.action(row.editAction.id, row.entry)
                    LogosToolTip { text: "Edit name"; visible: parent.hovered; delay: 400 }
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
                    onCopied: function (v) { row.copied(v) }
                    LogosToolTip { text: "Copy address"; visible: parent.hovered; delay: 400 }
                }
                Item { Layout.fillWidth: true }
            }
        }

        Repeater {
            model: row.otherActs
            delegate: LogosButton {
                required property var modelData
                objectName: row.namePrefix + "Action_" + Roster.actionName(modelData)
                text: modelData.label
                enabled: modelData.enabled
                // Compact where the app's design system has it; older pins lack the property.
                Component.onCompleted: if ("compact" in this) this["compact"] = true
                onClicked: row.action(modelData.id, row.entry)
                LogosToolTip { text: parent.modelData.tip; visible: parent.hovered && parent.modelData.tip.length > 0; delay: 400 }
            }
        }
        LogosIconButton {
            objectName: row.namePrefix + "Remove"
            visible: !!row.removeAction
            enabled: !row.removeAction || row.removeAction.enabled !== false
            Layout.alignment: Qt.AlignVCenter
            flat: true; size: 28; iconSize: 16
            iconSource: row.trashIcon
            iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
            onClicked: if (row.removeAction) row.action(row.removeAction.id, row.entry)
            LogosToolTip {
                text: (row.removeAction && row.removeAction.tip) ? row.removeAction.tip : "Remove"
                visible: parent.hovered; delay: 400
            }
        }
    }
}
