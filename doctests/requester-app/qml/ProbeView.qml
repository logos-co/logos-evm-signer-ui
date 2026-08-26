import QtQuick
import Logos.Controls
import Logos.Theme

// Deliberately inert.
//
// This fixture exists for its metadata, not its pixels: declaring
// `signer_probe` as a dependency is what makes the host load the requesting
// module at startup — the same way a wallet app pulls in its backend module.
// Nothing here is ever driven by the doc-test.
Item {
    anchors.fill: parent
    Rectangle { anchors.fill: parent; color: Theme.palette.background }
    LogosText {
        anchors.centerIn: parent
        text: "The requester module runs in the background.\nOpen the Signer app to approve what it asks for."
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
    }
}
