// Servicing an intent, LOADED and DRIVEN, with no shell, no host and no keystore.
//
// The e2e spec beside this proves the plugin signs. It cannot reach the intent half at all:
// there is no shell in `logos-standalone-app` to dispatch one. So `logos` is fabricated here
// as a QtObject with a REAL `intentRequested` signal — a plain JS object has no signals, and
// `Connections { target: logos }` would bind to nothing and quietly measure nothing.
//
// What is asserted is every way a request can end, because ending exactly once is the whole
// contract: approved, rejected, walked away from, displaced by a second dispatch, and named
// by a handle this keystore does not hold.
import QtQuick

Item {
    id: probe
    width: 900
    height: 700

    readonly property string handleA: "apr_aaa111"
    readonly property string handleB: "apr_bbb222"
    readonly property string bundleA: "bundle_aaa"

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

    // ── the fabricated shell ──────────────────────────────────────────────────
    //
    // A QtObject so `intentRequested` is a real signal the view's Connections can bind to,
    // and so `respond` can be recorded rather than routed.
    property var responses: []

    function lastResponse() {
        return probe.responses.length ? probe.responses[probe.responses.length - 1]
                                      : ({ requestId: "<none>", ok: "<none>", error: "<none>" })
    }
    function responsesFor(id) {
        return probe.responses.filter(function (r) { return r.requestId === id })
    }

    // TOTAL, deliberately. An assertion that FAILS must not then throw: the exception aborts
    // the run, and a probe that dies half way prints a header with silence under it — which
    // reads as a pass to anything scanning the log. Proven by mutation: removing the
    // displacement answer made this file report `got=0` and then die on `[0].error`.
    function responseAt(id, i) {
        var rs = probe.responsesFor(id)
        return rs.length > i ? rs[i] : ({ requestId: id, ok: "<none>", error: "<none>" })
    }

    QtObject {
        id: shell

        signal intentRequested(string requestId, string intent, var params, string requesterName)
        signal viewModuleReadyChanged(string moduleName, bool isReady)

        function module(n) { return fake }
        function isViewModuleReady(n) { return true }

        // The real bridge hands a pending call to a callback. Nothing here is asynchronous,
        // so the value is delivered straight through — what is under test is what the view
        // DOES with the answer, not how it waits for one.
        function watch(value, cb) { if (cb) cb(value) }

        function respond(requestId, ok, data, error) {
            var r = probe.responses
            r.push({ requestId: requestId, ok: ok, error: error })
            probe.responses = r
        }
    }

    property var logos: shell

    // ── the fabricated keystore-facing backend ────────────────────────────────
    //
    // `acknowledge` is the one with a decision in it: false for a handle the keystore does
    // not hold, which is what the view has to be able to tell from a serviceable one.
    QtObject {
        id: fake

        property string statusText: "Ready"
        property string lastError: ""
        property string pendingJson: "[]"
        property string renderedHandle: ""
        property string renderedBundleId: ""
        property string renderedRequester: ""
        property var renderLines: []
        property var interpretationLines: []
        property bool dwellElapsed: true

        // Handles this keystore holds. Anything else is unknown to it.
        property var known: [probe.handleA, probe.handleB]
        property var acknowledged: []

        signal settled(string handle, string state)

        function refresh() {}

        function acknowledge(handle) {
            var a = fake.acknowledged
            a.push(handle)
            fake.acknowledged = a
            if (fake.known.indexOf(handle) < 0) {
                fake.lastError = "could not open that request"
                fake.renderedHandle = ""
                return false
            }
            fake.lastError = ""
            fake.renderedHandle = handle
            fake.renderedBundleId = probe.bundleA
            fake.renderedRequester = "eth_wallet_backend"
            fake.renderLines = ["Account: 0xf39F…2266", "Send 0.1 ETH"]
            return true
        }

        function approve(handle, bundleId, password) { return true }
        function reject(handle) { return true }
        function dismiss() { fake.renderedHandle = "" }
    }

    function dispatch(requestId, handle) {
        shell.intentRequested(requestId, "evm.signing.approve",
                              { handle: handle }, "eth_wallet_ui")
    }

    // ── what the handler does on arrival ──────────────────────────────────────

    function assertItOpensTheNamedRequest() {
        console.log("")
        console.log("the shell dispatches, naming a handle. The view has to open THAT request")
        console.log("and not whatever happens to be at the top of the queue — a signer that")
        console.log("shows the wrong transaction is the failure this whole surface exists to")
        console.log("prevent")
        probe.dispatch("req-1", probe.handleB)
        check("the named handle was opened",
              JSON.stringify(fake.acknowledged), JSON.stringify([probe.handleB]))
        check("...and it is what is on screen", fake.renderedHandle, probe.handleB)
        check("nothing was answered yet", probe.responses.length, 0)
    }

    function assertAnIntentForAnotherNameIsIgnored() {
        console.log("")
        console.log("an intent this app does not provide passes straight through. A provider")
        console.log("that answered someone else's request would end it for them")
        var acksBefore = fake.acknowledged.length
        shell.intentRequested("req-other", "evm.accounts.manage", { handle: probe.handleA },
                              "eth_wallet_ui")
        check("nothing was opened", fake.acknowledged.length, acksBefore)
        check("...and nothing was answered", probe.responses.length, 0)
    }

    // ── every way a request ends ──────────────────────────────────────────────

    function assertApprovalEndsIt() {
        console.log("")
        console.log("the human approves. The answer comes from the keystore's own settle")
        console.log("event, not from the button: a request can settle from the queue by hand")
        console.log("or from a surface that is not this one, and an intent answered on a click")
        console.log("would stay open for ever in exactly those cases")
        fake.settled(probe.handleB, "approved")
        check("the request ended", probe.responsesFor("req-1").length, 1)
        check("...as a success", probe.lastResponse().ok, true)
        check("...with no error", probe.lastResponse().error, "")

        console.log("")
        console.log("and exactly once. A second settle for the same handle has nothing left")
        console.log("to answer — the map entry went with the first")
        fake.settled(probe.handleB, "approved")
        check("a repeat settle answers nothing", probe.responsesFor("req-1").length, 1)
    }

    function assertRejectionEndsItAsCancelled() {
        console.log("")
        console.log("the human says no. That is `cancelled`, not `failed`: the user backing")
        console.log("out is the system working, and a requester has to tell it from a signer")
        console.log("that could not be reached")
        probe.dispatch("req-2", probe.handleA)
        fake.settled(probe.handleA, "rejected")
        check("the request ended", probe.responsesFor("req-2").length, 1)
        check("...as a refusal", probe.lastResponse().ok, false)
        check("...named cancelled", probe.lastResponse().error, "cancelled")
    }

    function assertAnUnknownHandleIsABadRequest() {
        console.log("")
        console.log("a handle this keystore does not hold — stale, or never real. No retry of")
        console.log("the same payload fixes that, which is what `bad_request` means. It is")
        console.log("also the shell's own answer for a payload IT refused, so neither reveals")
        console.log("whether the other was consulted")
        probe.dispatch("req-3", "apr_nosuch")
        check("the request ended", probe.responsesFor("req-3").length, 1)
        check("...as bad_request", probe.lastResponse().error, "bad_request")
        check("...and nothing is on screen", fake.renderedHandle, "")
    }

    function assertDisplacementEndsTheOneItReplaces() {
        console.log("")
        console.log("two dispatches, one sheet. `acknowledge` demotes whatever was rendered,")
        console.log("so the first request is about to become invisible with nobody answering")
        console.log("it. Ending it here costs its requester a wait; leaving it costs ten")
        console.log("minutes and then a `timeout` for a request that was never refused")
        probe.dispatch("req-4", probe.handleA)
        check("the first is on screen", fake.renderedHandle, probe.handleA)
        probe.dispatch("req-5", probe.handleB)

        check("the displaced request ended", probe.responsesFor("req-4").length, 1)
        check("...as cancelled, not failed", probe.responseAt("req-4", 0).error, "cancelled")
        check("the second took the sheet", fake.renderedHandle, probe.handleB)
        check("...and is still open", probe.responsesFor("req-5").length, 0)

        console.log("")
        console.log("and the displaced one's keystore record is untouched, so settling it")
        console.log("later must not answer an intent that is already closed")
        fake.settled(probe.handleA, "approved")
        check("no second answer for it", probe.responsesFor("req-4").length, 1)
    }

    function assertWalkingAwayEndsIt() {
        console.log("")
        console.log("Back closes the sheet without deciding and leaves the record queued. The")
        console.log("requester is told what the user just did: not now")
        var backBtn = find(view.item, "signerBackButton")
        if (!backBtn) {
            probe.failures++
            console.log("  FAIL  signerBackButton is not in the tree")
            return
        }
        backBtn.clicked()
        check("the open request ended", probe.responsesFor("req-5").length, 1)
        check("...as cancelled", probe.responseAt("req-5", 0).error, "cancelled")
        check("...and the sheet closed", fake.renderedHandle, "")
    }

    function assertASettleWithNoIntentAnswersNothing() {
        console.log("")
        console.log("the queue is drivable by hand, with no intent anywhere near it. A settle")
        console.log("for a handle nobody asked about must not manufacture an answer")
        var before = probe.responses.length
        fake.acknowledge(probe.handleA)
        fake.settled(probe.handleA, "approved")
        check("nothing was answered", probe.responses.length, before)
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

            probe.assertItOpensTheNamedRequest()
            probe.assertAnIntentForAnotherNameIsIgnored()
            probe.assertApprovalEndsIt()
            probe.assertRejectionEndsItAsCancelled()
            probe.assertAnUnknownHandleIsABadRequest()
            probe.assertDisplacementEndsTheOneItReplaces()
            probe.assertWalkingAwayEndsIt()
            probe.assertASettleWithNoIntentAnswersNothing()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../qml/SignerView.qml")
}
