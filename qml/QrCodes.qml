import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// A QR wallet's session drawn here: the codes that carry the request, then how the camera reads
// the answer. Fed verbatim from the scanner through the backend; no picture comes here.
ColumnLayout {
    id: panel
    property var backend
    readonly property var qr: {
        try { return JSON.parse(backend ? backend.qrJson : "{}") } catch (e) { return ({}) }
    }
    readonly property var frames: {
        try { return JSON.parse(backend ? backend.qrFramesJson : "[]") } catch (e) { return [] }
    }
    property int index: 0
    onFramesChanged: index = 0
    spacing: 8

    Timer {
        interval: Math.max(50, panel.qr.interval_ms || 200)
        running: panel.visible && panel.qr.step === "show" && panel.frames.length > 1
        repeat: true
        onTriggered: panel.index = (panel.index + 1) % panel.frames.length
    }

    LogosText {
        Layout.fillWidth: true
        text: panel.qr.hint || ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    // Dark modules on white whatever the theme, with the quiet zone a reader needs.
    Canvas {
        objectName: "unlockQrCode"
        visible: panel.qr.step === "show" && panel.frames.length > 0
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 360
        Layout.preferredHeight: 360
        property var frame: panel.frames.length > 0 ? panel.frames[panel.index % panel.frames.length] : null
        onFrameChanged: requestPaint()
        onVisibleChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.fillStyle = "#ffffff"
            ctx.fillRect(0, 0, width, height)
            if (!frame) return
            var quiet = 4
            var side = Math.min(width, height)
            var m = Math.floor(side / (frame.size + 2 * quiet))
            var off = Math.floor((side - m * frame.size) / 2)
            ctx.fillStyle = "#000000"
            for (var y = 0; y < frame.size; y++)
                for (var x = 0; x < frame.size; x++)
                    if (frame.bits.charAt(y * frame.size + x) === "1")
                        ctx.fillRect(off + x * m, off + y * m, m, m)
        }
    }
    LogosText {
        visible: panel.qr.step === "scan"
        Layout.fillWidth: true
        text: panel.qr.seeing === true ? "A code is in view: hold it steady."
                                       : "No code in view yet: hold the wallet's answer up to the camera."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    LogosText {
        visible: (panel.qr.expected || 0) > 0
        text: "Read " + (panel.qr.received || 0) + " of " + (panel.qr.expected || 0) + " parts"
        textFormat: Text.PlainText
    }
    LogosButton {
        objectName: "unlockQrStep"
        visible: (panel.qr.label || "") !== ""
        text: panel.qr.label || ""
        onClicked: panel.backend.qrPress()
    }
}
