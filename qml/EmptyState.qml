import QtQuick 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// Centered empty state, matching the Keycard app: a bold title and a one-line explanation,
// horizontally centred in the available width. Used by the Requests and Wallets tabs.
Item {
    id: es
    property string title: ""
    property string subtitle: ""
    // Optional call to action under the explanation: a small, centred button.
    property string actionText: ""
    signal action()

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 2 * Theme.spacing.xxlarge

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.topMargin: Theme.spacing.xxlarge
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(es.width - 2 * Theme.spacing.large, 420)
        spacing: Theme.spacing.small

        LogosText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            font.pixelSize: Theme.typography.subtitleText
            font.weight: Theme.typography.weightBold
            color: Theme.palette.text
            text: es.title
        }
        LogosText {
            visible: es.subtitle !== ""
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: Theme.palette.textSecondary
            text: es.subtitle
        }
        LogosButton {
            objectName: "emptyStateAction"
            visible: es.actionText !== ""
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.spacing.small
            variant: LogosButton.Variant.Primary
            text: es.actionText
            onClicked: es.action()
        }
    }
}
