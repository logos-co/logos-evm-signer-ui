// "Sign with": an account several signers hold, and the person choosing which one signs. The
// backend is fabricated and answers as the manager would: the request stays the same, and only who
// signs, and what that signer asks for, changes.
import QtQuick

Item {
    id: probe
    width: 900
    height: 1000

    property int failures: 0

    function check(label, got, want) {
        var ok = String(got) === String(want)
        if (!ok)
            probe.failures++
        console.log((ok ? "  PASS  " : "  FAIL  ") + label + "   got=" + got
                    + (ok ? "" : "  want=" + want))
    }

    function findAll(o, name, out) {
        if (!o)
            return out
        if (o.objectName === name)
            out.push(o)
        var kids = o.data !== undefined ? o.data : []
        for (var i = 0; i < kids.length; ++i)
            findAll(kids[i], name, out)
        return out
    }
    function find(o, name) {
        var all = findAll(o, name, [])
        return all.length ? all[0] : null
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

    // The keystore, a Shell over USB, a QR wallet, and a card whose reader is empty.
    readonly property var four: [
        { signer: "keystore_module", accountId: "0xabc", kind: "keystore", model: "", transport: "keystore",
          presence: "local", available: true, collects: "password", showsRequest: false, canTake: true },
        { signer: "keycard_shell_module", accountId: "0xabc", kind: "keycard_shell", model: "Keycard Shell",
          transport: "usb", presence: "connected", available: true, collects: "nothing", showsRequest: true,
          canTake: true },
        { signer: "qr_signer_module", accountId: "0xabc", kind: "qr", model: "Keycard Shell", transport: "qr",
          presence: "on_demand", available: true, collects: "nothing", showsRequest: true, canTake: true },
        { signer: "keycard_module", accountId: "0xabc", kind: "keycard", model: "", transport: "reader",
          presence: "absent", available: false, collects: "pin", showsRequest: false, canTake: true }
    ]

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
        property bool renderedUnlocked: false
        property string renderedSignersJson: "[]"
        property bool renderedSignerExplicit: false
        property bool renderedSigning: false
        property string unattendedJson: "[]"
        property string qrJson: "{}"
        property string qrFramesJson: "[]"
        property var claimLines: []
        property var renderLines: []
        property var interpretationLines: []
        property bool dwellElapsed: true

        property var holders: []
        property var chosen: []

        signal settled(string handle, string state)

        function refresh() {}
        function refreshUnattended() {}
        function show(handle, holders) {
            fake.holders = holders
            fake.renderedSigning = false
            fake.renderedRequester = "eth_wallet_backend"
            fake.renderLines = ["Account: 0xabc", "Commitment: abcd"]
            fake.pick(holders[0].signer, false)
            fake.renderedHandle = handle
        }
        function pick(signer, explicit) {
            for (var i = 0; i < fake.holders.length; ++i) {
                if (fake.holders[i].signer === signer) {
                    fake.renderedSigner = signer
                    fake.renderedCollects = fake.holders[i].collects
                }
            }
            fake.renderedSignerExplicit = explicit
            fake.renderedSignersJson = JSON.stringify(fake.holders)
        }
        function acknowledge(handle) { return true }
        function chooseSigner(handle, signer) {
            var c = fake.chosen
            c.push(signer)
            fake.chosen = c
            fake.pick(signer, true)
            return true
        }
        function approve(handle, bundleId, password) { return true }
        function reject(handle) { return true }
        function dismiss() { fake.renderedHandle = "" }
        function qrPress() { return false }
        function qrCancel() { return false }
    }

    function rows() { return probe.findAll(view.item, "signWithRow", []) }
    function row(i) { return probe.rows()[i] }
    function part(i, name) { return probe.find(probe.row(i), name) }
    function password() { return probe.find(view.item, "vaultPasswordField") }

    function assertOneSignerKeepsTheLine() {
        console.log("")
        console.log("an account only one signer holds reads as before: one line, nothing to choose")
        fake.show("smh_1", [probe.four[0]])
        check("the signer line shows", probe.find(view.item, "signerLine").visible, true)
        check("...naming the holder as the chooser does", probe.find(view.item, "signerLine").text,
              "Signs with: This device (Keystore) — asks for the account's password")
        check("...and no chooser", probe.find(view.item, "signWith").visible, false)
        check("no way to the keys app to skip the password", probe.find(view.item, "signerUnlockLink"), null)
    }

    function assertASignerTheManagerDoesNotListKeepsItsId() {
        console.log("")
        console.log("a signer missing from the manager's list is named by its module id")
        fake.show("smh_5", [probe.four[0]])
        fake.renderedSigner = "other_signer_module"
        check("the line", probe.find(view.item, "signerLine").text,
              "Signs with: other_signer_module — asks for the account's password")
    }

    function assertEveryHolderIsOffered() {
        console.log("")
        console.log("several hold it: each is offered, in the manager's order, saying how it signs")
        fake.show("smh_2", probe.four)
        check("the chooser shows", probe.find(view.item, "signWith").visible, true)
        check("...instead of the line", probe.find(view.item, "signerLine").visible, false)
        check("four rows", probe.rows().length, 4)
        check("the keystore first", probe.part(0, "signWithChoice").text, "This device (Keystore)")
        check("...chosen", probe.part(0, "signWithChoice").checked, true)
        check("...ready", probe.part(0, "signWithState").text, "ready")
        check("...asking for the password", probe.part(0, "signWithHow").text, "Asks for the account's password.")
        check("the Shell", probe.part(1, "signWithChoice").text, "Keycard Shell · USB")
        check("...connected", probe.part(1, "signWithState").text, "connected")
        check("...confirmed on it", probe.part(1, "signWithHow").text, "Confirm on the Shell when it asks.")
        check("QR, never called connected", probe.part(2, "signWithState").text, "")
        check("...by its codes", probe.part(2, "signWithHow").text,
              "Shows the request as codes here, then reads its answer.")
        check("the card, not connected", probe.part(3, "signWithState").text, "not connected")
        check("...saying how to use it", probe.part(3, "signWithHow").text,
              "Insert the card in a reader to sign with it.")
        check("...and can't be chosen", probe.row(3).enabled, false)
        check("the password is asked for", probe.password().visible, true)
    }

    function assertChoosingTheShellAsksNoPassword() {
        console.log("")
        console.log("choosing the Shell: the manager is told, the typed password goes, and none is asked")
        probe.password().text = "half-typed"
        probe.part(1, "signWithChoice").clicked()
        check("the manager was told", JSON.stringify(fake.chosen), JSON.stringify(["keycard_shell_module"]))
        check("the Shell is chosen", probe.part(1, "signWithChoice").checked, true)
        check("...and the keystore no longer", probe.part(0, "signWithChoice").checked, false)
        check("the typed password is cleared", probe.password().text, "")
        check("...and no password is asked", probe.password().visible, false)
    }

    function assertAHolderThatCannotTakeItSaysWhy() {
        console.log("")
        console.log("a holder that can't take this request says why, in the manager's words")
        var shell = JSON.parse(JSON.stringify(probe.four[1]))
        shell.canTake = false
        shell.why = "keycard_shell_module signs what it shows, and a bare digest can't be shown"
        fake.show("smh_3", [probe.four[0], shell])
        check("the reason", probe.part(1, "signWithHow").text, shell.why)
        check("...and it can't be chosen", probe.row(1).enabled, false)
    }

    function assertNothingIsChosenWhileSigning() {
        console.log("")
        console.log("approved, with the device working: the choice is made, and the line says who")
        fake.show("smh_4", probe.four)
        fake.pick("keycard_shell_module", true)
        fake.renderedSigning = true
        check("no chooser", probe.find(view.item, "signWith").visible, false)
        check("the line names the Shell", probe.find(view.item, "signerLine").text,
              "Signs with: Keycard Shell · USB — confirm on the device when it asks")
    }

    function assertACoveredRequestAsksNoPassword() {
        console.log("")
        console.log("the manager says this request needs no password: none is asked, and both lines say so")
        fake.show("smh_6", [probe.four[0]])
        fake.renderedUnlocked = true
        check("the line", probe.find(view.item, "signerLine").text,
              "Signs with: This device (Keystore) — no password needed for this request")
        check("no password field", probe.password().visible, false)
        fake.show("smh_7", probe.four)
        check("the keystore's row", probe.part(0, "signWithHow").text, "No password needed for this request.")
        fake.renderedUnlocked = false
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

            probe.assertOneSignerKeepsTheLine()
            probe.assertASignerTheManagerDoesNotListKeepsItsId()
            probe.assertEveryHolderIsOffered()
            probe.assertChoosingTheShellAsksNoPassword()
            probe.assertAHolderThatCannotTakeItSaysWhy()
            probe.assertNothingIsChosenWhileSigning()
            probe.assertACoveredRequestAsksNoPassword()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../qml/SignerView.qml")
}
