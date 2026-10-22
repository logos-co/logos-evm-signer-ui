// The Wallets view and the Unlock sheet, LOADED and DRIVEN, with no shell, no host and no
// signer manager: what each wallet says, what unlocking asks for by its rule and holder, a
// password typed again after the device answered, an app's open shown beside its wallet, a rule
// change with a new password, and the `wallets.unlock` intent ending once the wallet unlocks.
import QtQuick

Item {
    id: probe
    width: 1000
    height: 900

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
    function findAll(o, name, out) {
        out = out || []
        if (!o)
            return out
        if (o.objectName === name)
            out.push(o)
        var kids = o.data !== undefined ? o.data : []
        for (var i = 0; i < kids.length; ++i)
            findAll(kids[i], name, out)
        return out
    }
    function visibleAll(name) {
        return probe.findAll(view.item, name).filter(function (o) { return o.visible })
    }

    // ── the fabricated shell ──────────────────────────────────────────────────
    property var responses: []
    QtObject {
        id: shell
        signal intentRequested(string requestId, string intent, var params, string requesterName)
        signal viewModuleReadyChanged(string moduleName, bool isReady)
        function module(n) { return fake }
        function isViewModuleReady(n) { return true }
        function watch(value, cb) { if (cb) cb(value) }
        function request(intent, params, cb) {}
        function respond(requestId, ok, data, error) {
            var r = probe.responses
            r.push({ requestId: requestId, ok: ok, error: error })
            probe.responses = r
        }
    }
    property var logos: shell

    // A card held in a reader and a Shell, "device only"; a QR wallet behind the device and the
    // password "Home"; and the password itself.
    readonly property var settings: ({
        wallets: [
            { seed: "s_card", name: "Card", locked: true, device: true, index: 0, generation: 0,
              holders: [{ signer: "keycard_module", seed: "uid", kind: "keycard" },
                        { signer: "keycard_shell_module", seed: "mkid", kind: "keycard_shell" }],
              ways: [{ id: "w_dev", factors: [{ kind: "device" }] }] },
            { seed: "s_qr", name: "Keystone", locked: true, device: true, index: 0, generation: 0,
              holders: [{ signer: "qr_signer_module", seed: "fp", kind: "qr" }],
              ways: [{ id: "w_both", factors: [{ kind: "device" }, { kind: "password", id: "p_home", name: "Home" }] }] }
        ],
        passwords: [{ id: "p_home", name: "Home", wallets: ["s_qr"] }]
    })

    // ── the fabricated backend ────────────────────────────────────────────────
    QtObject {
        id: fake

        property string statusText: "Ready"
        property string lastError: ""
        property string pendingJson: "[]"
        property string renderedHandle: ""
        property string renderedBundleId: ""
        property string renderedRequester: ""
        property string renderedSigner: ""
        property string renderedCollects: ""
        property string renderedSignersJson: "[]"
        property bool renderedSignerExplicit: false
        property bool renderedUnlocked: false
        property string renderedAccount: ""
        property string unattendedJson: "[]"
        property var claimLines: []
        property var renderLines: []
        property var interpretationLines: []
        property bool dwellElapsed: true
        property string qrJson: "{}"
        property string qrFramesJson: "[]"

        property string walletsJson: JSON.stringify(probe.settings)
        property string rosterJson: "[]"
        property string walletError: ""
        property string unlockJson: "{}"
        property string opensJson: "[]"
        property string openJson: "{}"

        property var calls: []
        function record(name, args) {
            var c = fake.calls
            c.push({ name: name, args: args })
            fake.calls = c
        }
        function last(name) {
            for (var i = fake.calls.length - 1; i >= 0; i--)
                if (fake.calls[i].name === name) return fake.calls[i].args
            return null
        }

        signal settled(string handle, string state)
        signal unlockEnded(string seed, bool ok)
        signal openSettled(string handle, string state)

        function refresh() {}
        function refreshUnattended() {}
        function refreshWallets() {}
        function acknowledge(handle) { return false }
        function dismiss() {}
        function unlockWallet(seed, way, holder, secret, passwords) {
            fake.record("unlockWallet", [seed, way, holder, secret, passwords])
            return true
        }
        function retryUnlock(passwords) { fake.record("retryUnlock", [passwords]); return true }
        function cancelUnlock() { fake.record("cancelUnlock", []); fake.unlockJson = "{}"; return true }
        function lockWallets(seeds) { fake.record("lockWallets", [seeds]); return true }
        function setRule(seed, ways, holder, secret, passwords) {
            fake.record("setRule", [seed, ways, holder, secret, passwords])
            return true
        }
        function changeKeys(seed, newIndex, holder, secret, passwords) {
            fake.record("changeKeys", [seed, newIndex, holder, secret, passwords])
            return true
        }
        function setNames(seed, name, privateName) { fake.record("setNames", [seed, name, privateName]); return true }
        function createPassword(name, password) { fake.record("createPassword", [name, password]); return "p_new" }
        function renamePassword(id, name) { return true }
        function changePassword(id, o, n) { return true }
        function removePassword(id) { return true }
        function showOpen(handle) {
            fake.record("showOpen", [handle])
            fake.openJson = JSON.stringify({ handle: handle, bundle_id: "bundle_open", requester: "bitcoin_wallet_core_module",
                                             kind: "open", seed: "s_card",
                                             lines: ["bitcoin_wallet_core_module asks to open a Bitcoin wallet"] })
            return true
        }
        function consentOpen(handle, bundleId, group) { fake.record("consentOpen", [handle, bundleId, group]); return true }
        function rejectOpen(handle) { fake.record("rejectOpen", [handle]); return true }
        function qrPress() { return true }
        function qrCancel() { return true }
    }

    function sheet() { return probe.find(view.item, "unlockSheet") }
    function unlockFor(seed) {
        view.item.openUnlock(seed, "")
    }
    function setUnlocked(seed, locked) {
        var s = JSON.parse(fake.walletsJson)
        s.wallets.forEach(function (w) { if (w.seed === seed) w.locked = locked })
        fake.walletsJson = JSON.stringify(s)
    }
    function type(objectName, text) {
        var fields = probe.visibleAll(objectName)
        if (fields.length === 0) { check("a visible " + objectName, "none", "one"); return }
        fields[0].text = text
    }
    function click(objectName) {
        var b = probe.visibleAll(objectName)
        if (b.length === 0) { check("a visible " + objectName, "none", "one"); return }
        b[0].clicked()
    }

    function assertEachWalletSaysHowItUnlocks() {
        console.log("")
        console.log("the Wallets tab lists every wallet with its holders and its rule, locked or not")
        view.item.page = 1
        var names = probe.findAll(view.item, "walletName").map(function (t) { return t.text })
        check("both wallets are listed", JSON.stringify(names), JSON.stringify(["Card", "Keystone"]))
        var rules = probe.findAll(view.item, "walletRule").map(function (t) { return t.text })
        check("device only", rules[0], "Unlocks with the device.")
        check("device and a password", rules[1], "Unlocks with the device and the password “Home”.")
        check("nothing to lock yet", probe.find(view.item, "lockAllButton").enabled, false)
    }

    function assertACardAsksForItsPinAndTheShellForAPress() {
        console.log("")
        console.log("unlocking the card's wallet asks which holder, and the card's PIN; the Shell asks nothing here")
        probe.unlockFor("s_card")
        check("the sheet is up", probe.sheet().visible, true)
        check("the unlock button waits for the PIN", probe.find(view.item, "unlockButton").enabled, false)
        probe.type("stepSecretField", "123456")
        check("...and arms once typed", probe.find(view.item, "unlockButton").enabled, true)
        probe.click("unlockButton")
        var args = fake.last("unlockWallet")
        check("the card is asked with its PIN", JSON.stringify(args),
              JSON.stringify(["s_card", "w_dev", "keycard_module", "123456", "{}"]))
        check("the PIN is cleared from the field", probe.find(view.item, "stepSecretField").text, "")

        var holders = probe.visibleAll("stepHolder")
        check("two holders to pick from", holders.length, 2)
        holders[1].clicked()
        check("no secret for the Shell", probe.visibleAll("stepSecretField").length, 0)
        probe.click("unlockButton")
        check("the Shell is asked, with nothing typed", JSON.stringify(fake.last("unlockWallet")),
              JSON.stringify(["s_card", "w_dev", "keycard_shell_module", "", "{}"]))
        fake.unlockJson = JSON.stringify({ handle: "smu_1", seed: "s_card", holder: "keycard_shell_module",
                                           state: "device", step: "confirm_on_device" })
        check("it says to confirm on the Shell", probe.find(view.item, "unlockWorking").text,
              "Confirm on the Shell: it asks to unlock this wallet.")
        probe.click("unlockClose")
        check("closing while it works cancels the step", fake.last("cancelUnlock") !== null, true)
        check("...and the sheet goes", probe.sheet().visible, false)
    }

    function assertAMistypedPasswordIsTypedAgainWithoutTheDevice() {
        console.log("")
        console.log("the QR wallet's way takes its device and the password Home; a wrong password, once")
        console.log("the device answered, is typed again without another round trip")
        probe.unlockFor("s_qr")
        probe.type("stepPasswordField", "hunter2")
        probe.click("unlockButton")
        check("the QR wallet is asked, with the password by its id", JSON.stringify(fake.last("unlockWallet")),
              JSON.stringify(["s_qr", "w_both", "qr_signer_module", "", JSON.stringify({ p_home: "hunter2" })]))
        fake.unlockJson = JSON.stringify({ handle: "smu_2", seed: "s_qr", holder: "qr_signer_module",
                                           state: "needs_password", error: "the password \"Home\" is not correct" })
        check("it says the device answered", probe.find(view.item, "unlockRetype").visible, true)
        probe.type("stepPasswordField", "hunter22")
        probe.click("unlockRetry")
        check("only the password goes again", JSON.stringify(fake.last("retryUnlock")),
              JSON.stringify([JSON.stringify({ p_home: "hunter22" })]))
        fake.unlockJson = "{}"
        view.item.closeUnlock(false)
    }

    function assertAnOpenWaitsBesideItsWalletForConsent() {
        console.log("")
        console.log("an app's open is listed under its wallet; reviewing it shows it in the sheet, and")
        console.log("consent is armed only once the wallet is unlocked")
        fake.opensJson = JSON.stringify([{ handle: "sma_1", requester: "bitcoin_wallet_core_module", kind: "open",
                                           state: "offered", ageMs: 10, seed: "s_card" }])
        check("listed under the card's wallet", probe.findAll(view.item, "walletOpen").length, 1)
        probe.click("walletOpenReview")
        check("shown in the sheet", JSON.stringify(fake.last("showOpen")), JSON.stringify(["sma_1"]))
        check("the request's own lines", probe.findAll(view.item, "unlockOpenLine")[0].text,
              "bitcoin_wallet_core_module asks to open a Bitcoin wallet")
        check("no consent while locked", probe.find(view.item, "unlockOpenConsent").enabled, false)
        probe.setUnlocked("s_card", false)
        check("consent once unlocked", probe.find(view.item, "unlockOpenConsent").enabled, true)
        probe.click("unlockOpenConsent")
        check("consent for that request", JSON.stringify(fake.last("consentOpen")),
              JSON.stringify(["sma_1", "bundle_open", ""]))
        fake.openSettled("sma_1", "approved")
        check("the sheet closes once it's open", probe.sheet().visible, false)
        fake.opensJson = "[]"
        fake.openJson = "{}"
    }

    function assertARuleWithANewPasswordCreatesItFirst() {
        console.log("")
        console.log("the card's rule moves to the device and a new password: the password is made first,")
        console.log("then the rule, which takes the device again for its new way")
        view.item.openRule("s_card", "rule")
        var choices = probe.visibleAll("ruleChoice")
        check("three rules on offer for a device", choices.length, 3)
        choices[1].clicked()
        probe.click("ruleNewPassword")
        probe.type("ruleNewPasswordName", "Work")
        probe.type("ruleNewPasswordField", "longenough")
        probe.type("ruleNewPasswordAgain", "longenough")
        probe.type("stepSecretField", "123456")
        probe.click("ruleApply")
        check("the password is made", JSON.stringify(fake.last("createPassword")), JSON.stringify(["Work", "longenough"]))
        var args = fake.last("setRule")
        check("then the rule, device and that password", args ? args[1] : "", JSON.stringify([["device", "password:p_new"]]))
        check("...through the card, with its PIN", args ? args[2] + " " + args[3] : "", "keycard_module 123456")
        check("...and the new password's typed value", args ? args[4] : "", JSON.stringify({ p_new: "longenough" }))
        fake.unlockEnded("s_card", true)
        check("the rule sheet closes once done", probe.find(view.item, "ruleSheet").visible, false)
    }

    function assertLockAllLocksEveryWallet() {
        console.log("")
        console.log("Lock all, once something is unlocked, locks every wallet")
        check("armed", probe.find(view.item, "lockAllButton").enabled, true)
        probe.click("lockAllButton")
        check("every wallet", JSON.stringify(fake.last("lockWallets")), JSON.stringify(["[]"]))
        probe.setUnlocked("s_card", true)
    }

    function assertTheUnlockIntentEndsOnceTheWalletUnlocks() {
        console.log("")
        console.log("an app asks to unlock a wallet: the sheet opens for it, and the ask ends once it's unlocked")
        shell.intentRequested("req-u", "wallets.unlock", { seeds: ["s_qr"] }, "eth_wallet_ui")
        check("the sheet is up for that wallet", probe.sheet().visible && probe.sheet().seed === "s_qr", true)
        check("nothing answered yet", probe.responses.length, 0)
        fake.unlockEnded("s_qr", true)
        check("answered once unlocked", probe.responses.length === 1 && probe.responses[0].ok === true, true)
        check("...and the sheet goes", probe.sheet().visible, false)

        shell.intentRequested("req-v", "wallets.unlock", {}, "eth_wallet_ui")
        probe.click("unlockClose")
        check("closed without unlocking: cancelled", probe.responses.length === 2 && probe.responses[1].error === "cancelled", true)
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

            probe.assertEachWalletSaysHowItUnlocks()
            probe.assertACardAsksForItsPinAndTheShellForAPress()
            probe.assertAMistypedPasswordIsTypedAgainWithoutTheDevice()
            probe.assertAnOpenWaitsBesideItsWalletForConsent()
            probe.assertARuleWithANewPasswordCreatesItFirst()
            probe.assertLockAllLocksEveryWallet()
            probe.assertTheUnlockIntentEndsOnceTheWalletUnlocks()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../qml/SignerView.qml")
}
