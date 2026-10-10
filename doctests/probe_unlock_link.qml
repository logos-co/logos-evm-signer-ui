// The Signer's way to the keys app for an unlock, with `logos.request` recorded and answered by
// hand: the e2e host has no shell, so no intent it raises goes anywhere.
import QtQuick

Item {
    id: probe
    width: 900
    height: 700

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

    // ── the fabricated shell: requests are kept, with the callback each waits on ──
    property var requests: []
    function lastRequest() {
        return probe.requests.length ? probe.requests[probe.requests.length - 1]
                                     : ({ intent: "<none>", params: ({}), cb: function () {} })
    }
    function answer(ok, error) {
        probe.lastRequest().cb({ ok: ok, data: ({}), error: error })
    }

    QtObject {
        id: shell

        signal intentRequested(string requestId, string intent, var params, string requesterName)
        signal viewModuleReadyChanged(string moduleName, bool isReady)

        function module(n) { return fake }
        function isViewModuleReady(n) { return true }
        function watch(value, cb) { if (cb) cb(value) }
        function respond(requestId, ok, data, error) {}
        function request(intent, params, cb) {
            var r = probe.requests
            r.push({ intent: intent, params: params, cb: cb })
            probe.requests = r
        }
    }

    property var logos: shell

    // ── the fabricated backend: a Bitcoin send from a wallet that is locked ──
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
        property string renderedAccount: ""
        property string unattendedJson: "[]"
        property var claimLines: []
        property var renderLines: []
        property var interpretationLines: []
        property bool dwellElapsed: true

        // What the manager answers on the next acknowledge: an unlock may cover it by then.
        property bool coveredNext: false
        property string collectsNext: "password"
        property var acknowledged: []

        signal settled(string handle, string state)

        function refresh() {}
        function refreshUnattended() {}
        function acknowledge(handle) {
            var a = fake.acknowledged
            a.push(handle)
            fake.acknowledged = a
            fake.renderedRequester = "btc_wallet_core"
            fake.renderedSigner = "keystore_module"
            fake.renderedCollects = fake.collectsNext
            fake.renderedUnlocked = fake.coveredNext
            fake.renderedAccount = "g_0123abcd"
            fake.claimLines = ["Purpose (claimed by the requester): Pay the plumber"]
            fake.renderLines = ["Wallet: \"Savings\"", "Commitment: abcd"]
            fake.renderedHandle = handle
            return true
        }
        function approve(handle, bundleId, password) { return true }
        function reject(handle) { return true }
        function dismiss() { fake.renderedHandle = "" }
    }

    function link() { return probe.find(view.item, "signerUnlockLink") }
    function note() { return probe.find(view.item, "unlockNote") }
    function password() { return probe.find(view.item, "vaultPasswordField") }

    function assertALockedAccountOffersTheKeysApp() {
        console.log("")
        console.log("a request whose account is locked asks for its password, and offers the")
        console.log("keys app instead: unlocking is the keys app's, never the Signer's")
        fake.acknowledge("smh_1")
        check("the password field shows", probe.password().visible, true)
        check("...and so does the way to the keys app", probe.link().visible, true)
        check("nothing was asked yet", probe.requests.length, 0)
    }

    function assertItAsksForThisAccountForTheAppThatAsked() {
        console.log("")
        console.log("the keys app is asked for this request's account, offering the app that")
        console.log("asked as the one the unlock would cover; the person decides the terms there")
        probe.link().clicked()
        check("one request", probe.requests.length, 1)
        check("...for the keys app's unlock", probe.lastRequest().intent, "keystore.accounts.unlock")
        check("...naming the account", probe.lastRequest().params.account, "g_0123abcd")
        check("...and the app that asked", probe.lastRequest().params.app, "btc_wallet_core")
    }

    function assertAnUnlockReadsTheRequestAgain() {
        console.log("")
        console.log("the keys app answers ok: the request is read again, and an unlock that")
        console.log("now covers it means no password and no link")
        fake.coveredNext = true
        probe.answer(true, "")
        check("the same request was read again",
              JSON.stringify(fake.acknowledged), JSON.stringify(["smh_1", "smh_1"]))
        check("...and is now unlocked", fake.renderedUnlocked, true)
        check("no password field", probe.password().visible, false)
        check("no link", probe.link().visible, false)
        check("no note", probe.note().visible, false)
        fake.coveredNext = false
    }

    function assertACancelSaysNothing() {
        console.log("")
        console.log("the person backs out of the keys app: nothing to say, and nothing to read again")
        fake.acknowledge("smh_2")
        probe.link().clicked()
        var before = fake.acknowledged.length
        probe.answer(false, "cancelled")
        check("not read again", fake.acknowledged.length, before)
        check("no note", probe.note().visible, false)
        check("the password field stays", probe.password().visible, true)
    }

    function assertNoKeysAppIsSaid() {
        console.log("")
        console.log("no keys app could take it: the person is told, and the password still works")
        probe.link().clicked()
        probe.answer(false, "unavailable")
        check("a note", probe.note().visible, true)
        check("...that says so", probe.note().text, "No keys app could take this.")
        console.log("")
        console.log("and the note goes with the request it was about")
        fake.acknowledge("smh_3")
        check("the note is gone", probe.note().visible, false)
    }

    function assertALateAnswerForAnotherRequestReadsNothing() {
        console.log("")
        console.log("an answer that arrives after the screen moved on must not reopen the old request")
        probe.link().clicked()
        fake.acknowledge("smh_4")
        var before = fake.acknowledged.length
        probe.answer(true, "")
        check("nothing read again", fake.acknowledged.length, before)
        check("the new request stays on screen", fake.renderedHandle, "smh_4")
    }

    function assertOnlyAKeystorePasswordGetsTheLink() {
        console.log("")
        console.log("a card's PIN, or a device that asks the person itself, has nothing to unlock here")
        fake.collectsNext = "pin"
        fake.acknowledge("smh_5")
        check("no link for a PIN", probe.link().visible, false)
        fake.collectsNext = "nothing"
        fake.acknowledge("smh_6")
        check("no link for a device", probe.link().visible, false)
        fake.collectsNext = "password"
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

            probe.assertALockedAccountOffersTheKeysApp()
            probe.assertItAsksForThisAccountForTheAppThatAsked()
            probe.assertAnUnlockReadsTheRequestAgain()
            probe.assertACancelSaysNothing()
            probe.assertNoKeysAppIsSaid()
            probe.assertALateAnswerForAnotherRequestReadsNothing()
            probe.assertOnlyAKeystorePasswordGetsTheLink()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../qml/SignerView.qml")
}
