// Three sections, and the requester's words confined to the first of them.
//
// The keystore hands an approver two lists precisely so this surface can keep them
// apart. Nothing in the C++ or the QML compiler can tell whether it did: appending
// `claimLines` to `renderLines` in the view would render identically to a reader
// scanning a screenshot, and would put requester-authored text under the heading that
// says "this is what the signature will cover". So it is asserted here, by walking
// each section's own subtree and reading the lines that actually landed in it.
import QtQuick

Item {
    id: probe
    width: 900
    height: 900

    readonly property string claim: "Purpose (claimed by the requester): Send 1 ETH to Alice"
    readonly property string signedLine: "Commitment: 9f86d081"
    readonly property string interpreted: "Interpreted: plain value transfer"

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

    // Every VISIBLE text under a subtree. Visibility matters: each section carries an
    // empty-state line that must not count while there is content, and an assertion
    // that ignored it would pass on a section showing both.
    function textsUnder(o, out) {
        out = out || []
        if (!o)
            return out
        if (o.text !== undefined && String(o.text) !== "" && o.visible)
            out.push(String(o.text))
        var kids = o.data !== undefined ? o.data : []
        for (var i = 0; i < kids.length; ++i)
            probe.textsUnder(kids[i], out)
        return out
    }

    function sectionTexts(name) {
        return probe.textsUnder(probe.find(view.item, name)).join("\n")
    }

    QtObject {
        id: shell
        signal intentRequested(string requestId, string intent, var params, string requesterName)
        signal viewModuleReadyChanged(string moduleName, bool isReady)
        function module(n) { return fake }
        function isViewModuleReady(n) { return true }
        function watch(value, cb) { if (cb) cb(value) }
        function respond(requestId, ok, data, error) {}
    }
    property var logos: shell

    QtObject {
        id: fake
        property string statusText: "Ready"
        property string lastError: ""
        property string pendingJson: "[]"
        property string renderedHandle: ""
        property string renderedBundleId: ""
        property string renderedRequester: ""
        property var claimLines: []
        property var renderLines: []
        property var interpretationLines: []
        property bool dwellElapsed: true

        signal settled(string handle, string state)
        function refresh() {}
        function approve(handle, bundleId, password) { return true }
        function reject(handle) { return true }
        function dismiss() { fake.renderedHandle = "" }

        function acknowledge(handle) {
            fake.renderedHandle = handle
            fake.renderedRequester = "eth_wallet_backend"
            fake.renderedBundleId = "9f86d081"
            fake.claimLines = [probe.claim]
            fake.renderLines = ["Account: 0xf39F…2266", probe.signedLine,
                                "  [1] Transaction on chain 1", "      Value: 0"]
            fake.interpretationLines = [probe.interpreted]
            return true
        }

        // A request whose requester said nothing, and whose calldata decoded to nothing.
        function acknowledgeBare(handle) {
            fake.renderedHandle = handle
            fake.renderedRequester = "eth_wallet_backend"
            fake.renderedBundleId = "9f86d081"
            fake.claimLines = []
            fake.renderLines = ["Account: 0xf39F…2266", probe.signedLine]
            fake.interpretationLines = []
            return true
        }
    }

    function assertAllThreeSectionsAreOnScreen() {
        console.log("")
        console.log("a request is on screen. Three sections, in the order a human reads them:")
        console.log("who is asking, what is signed, and what this signer makes of it")
        fake.acknowledge("apr_aaa111")
        check("section 1 exists", probe.find(view.item, "sectionRequester") !== null, true)
        check("section 2 exists", probe.find(view.item, "sectionSigned") !== null, true)
        check("section 3 exists", probe.find(view.item, "sectionInterpretation") !== null, true)
    }

    function assertEachSectionCarriesItsOwnLines() {
        console.log("")
        console.log("each list lands in its own section and nowhere else")
        check("the claim is in section 1",
              probe.sectionTexts("sectionRequester").indexOf(probe.claim) >= 0, true)
        check("what is signed is in section 2",
              probe.sectionTexts("sectionSigned").indexOf(probe.signedLine) >= 0, true)
        check("the reading is in section 3",
              probe.sectionTexts("sectionInterpretation").indexOf(probe.interpreted) >= 0, true)
    }

    function assertTheRequestersWordsStayOutOfWhatIsSigned() {
        console.log("")
        console.log("and this is the one that matters. The requester controls `purpose`")
        console.log("entirely. Under the heading that says the signature covers this, its")
        console.log("text would be a stranger writing in the keystore's hand")
        check("the claim is NOT in section 2",
              probe.sectionTexts("sectionSigned").indexOf(probe.claim) >= 0, false)
        check("...nor in section 3",
              probe.sectionTexts("sectionInterpretation").indexOf(probe.claim) >= 0, false)
        console.log("")
        console.log("and the requester is named from the keystore's own field, not from")
        console.log("anything the requester filled in")
        check("section 1 names who asked",
              probe.sectionTexts("sectionRequester").indexOf("eth_wallet_backend") >= 0, true)
    }

    function assertAnEmptySectionSaysSoRatherThanVanishing() {
        console.log("")
        console.log("a requester that gave no reason, and calldata nothing could decode. Both")
        console.log("sections stay and say they are empty: a section that disappeared would")
        console.log("renumber the others, and a blank one reads as a screen still loading")
        fake.acknowledgeBare("apr_bbb222")
        check("section 1 says the requester gave no reason",
              probe.sectionTexts("sectionRequester").indexOf("gave no reason") >= 0, true)
        check("section 3 says nothing decoded",
              probe.sectionTexts("sectionInterpretation").indexOf("nothing could be decoded") >= 0,
              true)
        check("section 2 still has the request", 
              probe.sectionTexts("sectionSigned").indexOf(probe.signedLine) >= 0, true)

        console.log("")
        console.log("and once there IS content the empty-state line is gone, not merely")
        console.log("pushed below it")
        fake.acknowledge("apr_aaa111")
        check("no empty-state line in section 1",
              probe.sectionTexts("sectionRequester").indexOf("gave no reason") >= 0, false)
        check("no empty-state line in section 3",
              probe.sectionTexts("sectionInterpretation").indexOf("nothing could be decoded") >= 0,
              false)
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

            probe.assertAllThreeSectionsAreOnScreen()
            probe.assertEachSectionCarriesItsOwnLines()
            probe.assertTheRequestersWordsStayOutOfWhatIsSigned()
            probe.assertAnEmptySectionSaysSoRatherThanVanishing()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../qml/SignerView.qml")
}
