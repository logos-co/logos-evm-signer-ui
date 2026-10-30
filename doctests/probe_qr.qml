// A QR wallet's request, drawn in the Signer where it was approved: the codes to show the wallet,
// then how its answer is read. The backend is fabricated; what the scanner would answer is set by
// hand. No picture ever reaches this view: only the codes and whether one is in view.
import QtQuick

Item {
    id: probe
    width: 900
    height: 1100

    property int failures: 0

    function check(label, got, want) {
        var ok = String(got) === String(want)
        if (!ok)
            probe.failures++
        console.log((ok ? "  PASS  " : "  FAIL  ") + label + "   got=" + got
                    + (ok ? "" : "  want=" + want))
    }

    function find(o, name) {
        if (!o)
            return null
        if (o.objectName === name)
            return o
        var kids = o.data !== undefined ? o.data : []
        for (var i = 0; i < kids.length; ++i) {
            var hit = find(kids[i], name)
            if (hit)
                return hit
        }
        return null
    }

    QtObject {
        id: shell

        signal intentRequested(string requestId, string intent, var params, string requesterName)
        signal viewModuleReadyChanged(string moduleName, bool isReady)

        function module(n) { return fake }
        function isViewModuleReady(n) { return true }
        function watch(value, cb) { if (cb) cb(value) }
        function respond(requestId, ok, data, error) {}
        function request(intent, params, cb) {}
    }

    property var logos: shell

    // A version 1 code: 21 by 21 modules, alternating.
    function bits() {
        var s = ""
        for (var i = 0; i < 21 * 21; ++i)
            s += (i % 2) ? "1" : "0"
        return s
    }

    QtObject {
        id: fake

        property string statusText: "Ready"
        property string lastError: ""
        property string pendingJson: "[]"
        property string renderedHandle: ""
        property string renderedBundleId: "bundle"
        property string renderedRequester: ""
        property string renderedSigner: ""
        property string renderedCollects: ""
        property string renderedSignersJson: "[]"
        property bool renderedSignerExplicit: false
        property bool renderedUnlocked: false
        property bool renderedSigning: false
        property string unattendedJson: "[]"
        property var claimLines: []
        property var renderLines: []
        property var interpretationLines: []
        property bool dwellElapsed: true
        property string qrJson: "{}"
        property string qrFramesJson: "[]"

        property int pressed: 0
        property int cancelled: 0

        signal settled(string handle, string state)

        function refresh() {}
        function refreshUnattended() {}
        function acknowledge(handle) {
            fake.renderedRequester = "bitcoin_wallet_backend"
            fake.renderedSigner = "qr_signer_module"
            fake.renderedCollects = "nothing"
            fake.renderLines = ["Commitment: abcd"]
            fake.renderedHandle = handle
            return true
        }
        function chooseSigner(handle, signer) { return false }
        function approve(handle, bundleId, password) { fake.renderedSigning = true; return true }
        function reject(handle) { return true }
        function dismiss() { fake.renderedHandle = ""; fake.renderedSigning = false }
        function qrPress() { fake.pressed++; return true }
        function qrCancel() { fake.cancelled++; return true }
    }

    function el(name) { return probe.find(view.item, name) }

    function assertNothingIsDrawnBeforeApproval() {
        console.log("")
        console.log("a QR wallet's request awaiting approval: no codes yet, only the request")
        fake.acknowledge("smh_1")
        fake.qrJson = JSON.stringify({ active: false, in_window: false, seeing: false })
        check("no QR panel", probe.el("qrPanel").visible, false)
        check("Approve still decides", probe.el("signerApproveButton").visible, true)
    }

    function assertApprovedCodesAreDrawnHere() {
        console.log("")
        console.log("approved: the codes are drawn here, with the step that follows, and no window")
        fake.renderedSigning = true
        fake.qrFramesJson = JSON.stringify([{ size: 21, bits: probe.bits() }])
        fake.qrJson = JSON.stringify({ active: true, step: "show", in_window: false, seeing: false,
            hint: "Scan these codes with your wallet and confirm on it, then press Scan the answer",
            label: "Scan the answer", interval_ms: 200, frames_id: "qrs_1" })
        check("the QR panel shows", probe.el("qrPanel").visible, true)
        check("...with the code", probe.el("qrCode").visible, true)
        check("...the hint", probe.el("qrHint").text,
              "Scan these codes with your wallet and confirm on it, then press Scan the answer")
        check("...and the next step", probe.el("qrStepButton").text, "Scan the answer")
        check("no camera line yet: the camera is off", probe.el("qrCamera").visible, false)
        check("not the generic device line", probe.el("deviceWaiting").visible, false)
        probe.el("qrStepButton").clicked()
        check("the step went to the scanner", fake.pressed, 1)
    }

    function assertTheAnswerIsReadWithoutAPicture() {
        console.log("")
        console.log("the camera reads the answer: whether a code is in view, and how much is read")
        fake.qrJson = JSON.stringify({ active: true, step: "scan", in_window: false, seeing: false,
            hint: "Hold your wallet's answer up to the camera", label: "Show the request again",
            interval_ms: 200, frames_id: "qrs_1" })
        check("the code is gone", probe.el("qrCode").visible, false)
        check("the camera line shows", probe.el("qrCamera").visible, true)
        check("...nothing in view yet", probe.el("qrCamera").text,
              "No code in view yet: hold the wallet's answer up to the camera.")
        fake.qrJson = JSON.stringify({ active: true, step: "scan", in_window: false, seeing: true,
            received: 3, expected: 10, label: "Show the request again", interval_ms: 200,
            frames_id: "qrs_1" })
        check("...a code in view", probe.el("qrCamera").text, "A code is in view: hold it steady.")
        check("...and the parts read", probe.el("qrProgress").text, "Read 3 of 10 parts")
        check("the way back to the request", probe.el("qrStepButton").text, "Show the request again")
    }

    function assertCancelAndBackStopTheCamera() {
        console.log("")
        console.log("Cancel ends the wallet's session; so does leaving, rather than leave the camera on")
        probe.el("qrCancelButton").clicked()
        check("Cancel went to the scanner", fake.cancelled, 1)
        probe.el("signerBackButton").clicked()
        check("Back cancelled it too", fake.cancelled, 2)
        check("...and closed the request", fake.renderedHandle, "")
    }

    function assertASessionInTheWindowIsSaid() {
        console.log("")
        console.log("a session that started in the Logos QR window stays there, and the sheet says so")
        fake.acknowledge("smh_2")
        fake.renderedSigning = true
        fake.qrJson = JSON.stringify({ active: false, step: "show", in_window: true, seeing: false })
        check("no QR panel", probe.el("qrPanel").visible, false)
        check("the window is named", probe.el("qrInWindow").visible, true)
        check("not the generic device line", probe.el("deviceWaiting").visible, false)
    }

    function assertOtherDevicesAreUnchanged() {
        console.log("")
        console.log("a device that isn't a QR wallet waits as before")
        fake.renderedSigner = "keycard_shell_module"
        fake.qrJson = "{}"
        check("no QR panel", probe.el("qrPanel").visible, false)
        check("no window line", probe.el("qrInWindow").visible, false)
        check("the device line", probe.el("deviceWaiting").visible, true)
    }

    Loader {
        id: view
        anchors.fill: parent
        onStatusChanged: {
            if (status === Loader.Error) {
                console.log("  FAIL  the view did not load")
                Qt.exit(1)
            }
            if (status !== Loader.Ready)
                return
            item.ready = true

            probe.assertNothingIsDrawnBeforeApproval()
            probe.assertApprovedCodesAreDrawnHere()
            probe.assertTheAnswerIsReadWithoutAPicture()
            probe.assertCancelAndBackStopTheCamera()
            probe.assertASessionInTheWindowIsSaid()
            probe.assertOtherDevicesAreUnchanged()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../qml/SignerView.qml")
}
