import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// The signing approval surface.
//
// This view renders the signer manager's own lines VERBATIM and collects the vault
// password. It never parses an intent — it has no client for any wallet module
// and could not decode one. Every line on screen came from the manager that will
// have the signature produced.
//
// Rendering rule: every text item in the request region sets
// `textFormat: Text.PlainText` explicitly. LogosText is a bare Text with no
// textFormat, i.e. Qt's AutoText HTML autodetection, so a line containing
// markup would otherwise render as markup. Nothing here elides or reformats.
Item {
    id: root
    anchors.fill: parent

    // Paint the surface. Without this the QQuickWidget's own (white) clear
    // colour shows through, and LogosText defaults to Theme.palette.text —
    // which is a LIGHT colour under the dark theme, so every label rendered
    // white-on-white and the view looked empty even though it had loaded.
    Rectangle {
        anchors.fill: parent
        color: Theme.palette.background
    }

    readonly property var backend: logos.module("evm_signer_ui")

    // `ready` must be a writable property fed by the bridge's signal, NOT a
    // binding. `logos.isViewModuleReady(...)` is a function call, and a
    // function call is not a reactive dependency: a binding containing one
    // evaluates once, at creation, when the ui-host has not finished handing
    // over yet — so it latches false forever and the view sits on "Connecting…"
    // with a backend that is in fact working.
    property bool ready: false

    // Intents being serviced, keyed by the manager handle each one named. A provider can
    // be dispatched more than once while a request is open and `acknowledge` shows exactly
    // one at a time, so this is what lets a displaced request be answered now rather than
    // left to the shell's ten-minute backstop.
    property var intentByHandle: ({})

    // ── wallets ─────────────────────────────────────────────────────────────
    // 0: the requests, 1: the wallets.
    property int page: 0
    onPageChanged: if (tabs.currentIndex !== page) tabs.currentIndex = page
    // The wallet the Unlock sheet is for, and the open that brought the person there, if any.
    property string unlockSeed: ""
    property string unlockOpen: ""
    property string ruleSeed: ""
    property string ruleMode: "rule"
    // The `wallets.unlock` intent being serviced, ended when the wallet unlocks or the sheet closes.
    property string unlockIntent: ""
    function parsed(raw, empty) {
        try { return JSON.parse(raw) } catch (e) { return empty }
    }
    function openUnlock(seed, openHandle) {
        root.page = 1
        root.unlockOpen = openHandle || ""
        root.unlockSeed = seed
    }
    function closeUnlock(ok) {
        root.unlockSeed = ""
        root.unlockOpen = ""
        if (root.unlockIntent !== "") {
            logos.respond(root.unlockIntent, ok, ({}), ok ? "" : "cancelled")
            root.unlockIntent = ""
        }
    }
    function openRule(seed, mode) {
        root.ruleMode = mode
        root.ruleSeed = seed
        ruleSheet.reset()
    }
    // What a `wallets.unlock` asks for: the wallet an open names, else the first locked wallet it
    // lists, else the first locked wallet.
    function unlockTarget(params) {
        var ws = root.parsed(backend.walletsJson, ({})).wallets || []
        var opens = root.parsed(backend.opensJson, [])
        if (params.openHandle)
            for (var i = 0; i < opens.length; i++)
                if (opens[i].handle === params.openHandle && opens[i].seed) return opens[i].seed
        var asked = params.seeds || []
        for (var j = 0; j < ws.length; j++)
            if (ws[j].locked && (asked.length === 0 || asked.indexOf(ws[j].seed) >= 0)) return ws[j].seed
        return asked.length > 0 ? asked[0] : ""
    }

    function answerIntent(handle, ok, error) {
        var id = root.intentByHandle[handle]
        if (id === undefined) return
        delete root.intentByHandle[handle]
        // Nothing renderable goes back. The requester learns the outcome from its own data
        // source; what it gets here is that the request ended, and how.
        logos.respond(id, ok, ({}), error)
    }

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "evm_signer_ui") root.ready = isReady && root.backend !== null
        }

        function onIntentRequested(requestId, intent, params, requesterName) {
            if (intent === "wallets.unlock") {
                // One at a time: a second ask while the sheet is up ends the first as displaced.
                if (root.unlockIntent !== "") logos.respond(root.unlockIntent, false, ({}), "cancelled")
                var seed = root.ready ? root.unlockTarget(params || {}) : ""
                if (seed === "") {
                    logos.respond(requestId, false, ({}), "bad_request")
                    return
                }
                root.unlockIntent = requestId
                root.openUnlock(seed, (params || {}).openHandle || "")
                return
            }
            if (intent !== "evm.signing.approve") return
            root.page = 0

            // Acknowledging demotes whatever is on screen, so an intent held for THAT
            // request is about to be displaced. End it here: its manager record is
            // untouched and its requester falls back to waiting, which is a better answer
            // than one that arrives as `timeout` ten minutes later.
            var shown = root.ready ? backend.renderedHandle : ""
            if (shown !== "" && shown !== params.handle)
                root.answerIntent(shown, false, "cancelled")

            root.intentByHandle[params.handle] = requestId
            logos.watch(backend.acknowledge(params.handle), function (opened) {
                // A handle the manager does not hold, or one already settled. No retry of
                // the same payload fixes that, which is what `bad_request` means — and it is
                // deliberately the same answer the shell gives for a payload it refused
                // itself, so neither reveals whether the other was consulted.
                if (!opened) root.answerIntent(params.handle, false, "bad_request")
            })
        }
    }

    // The authoritative end of a request, whichever way it ended. Answering from the buttons
    // below instead would leave an intent open whenever the human settled it from the queue,
    // or from a surface that is not this one.
    Connections {
        target: root.ready ? root.backend : null
        function onSettled(handle, state) {
            var approved = state === "approved"
            root.answerIntent(handle, approved, approved ? "" : "cancelled")
        }
        function onRenderedHandleChanged() { root.unlockNote = "" }
        // The sheet's step ended: the rule or keys sheet closes once done, and an unlock asked
        // for by an intent ends once the wallet is unlocked and no open waits beside it.
        function onUnlockEnded(seed, ok) {
            if (ok && seed === root.ruleSeed) root.ruleSeed = ""
            if (ok && seed === root.unlockSeed && root.unlockOpen === "" && root.unlockIntent !== "")
                root.closeUnlock(true)
        }
        function onOpenSettled(handle, state) {
            if (handle === root.unlockOpen) root.closeUnlock(state === "approved")
        }
    }

    // Unlocking is the keys app's. Send the person there for this request's account, for the
    // app that asked; once it answers, read the request again, since an unlock may now cover it.
    property string unlockNote: ""
    function unlockInKeysApp() {
        var handle = backend.renderedHandle
        root.unlockNote = ""
        logos.request("keystore.accounts.unlock",
                      ({ account: backend.renderedAccount, app: backend.renderedRequester }), function (res) {
            if (res.ok) {
                if (backend.renderedHandle === handle) backend.acknowledge(handle)
            } else if (res.error !== "cancelled") {
                root.unlockNote = res.error === "unavailable" ? "No keys app could take this."
                                                              : "The keys app did not unlock it (" + res.error + ")."
            }
        })
    }
    Component.onCompleted: root.ready = root.backend !== null && logos.isViewModuleReady("evm_signer_ui")
    readonly property var queue: {
        try { return JSON.parse(backend ? backend.pendingJson : "[]") } catch (e) { return [] }
    }
    readonly property bool showing: ready && backend.renderedHandle !== ""
    // No secret to type: an unlock covers this request, or its device asks the person itself.
    readonly property bool needsSecret: showing && !backend.renderedUnlocked && backend.renderedCollects !== "nothing"
    readonly property var unattended: {
        try { return JSON.parse(backend ? backend.unattendedJson : "[]") } catch (e) { return [] }
    }
    // A QR wallet's request, once approved: drawn here, where it was approved, as the codes that
    // carry it to the wallet; then how the camera reads its answer. No picture comes here.
    readonly property var qr: {
        try { return JSON.parse(backend ? backend.qrJson : "{}") } catch (e) { return ({}) }
    }
    readonly property var qrFrames: {
        try { return JSON.parse(backend ? backend.qrFramesJson : "[]") } catch (e) { return [] }
    }
    readonly property bool qrDrawing: showing && backend.renderedSigning === true && qr.active === true
    property int qrIndex: 0
    onQrFramesChanged: qrIndex = 0
    Timer {
        interval: Math.max(50, root.qr.interval_ms || 200)
        running: root.qrDrawing && root.qr.step === "show" && root.qrFrames.length > 1
        repeat: true
        onTriggered: root.qrIndex = (root.qrIndex + 1) % root.qrFrames.length
    }
    // The same words as evm_signer_cli's `signer:` line: one request reads alike on both.
    readonly property string signerLine: {
        if (!showing || backend.renderedSigner === "") return ""
        var how = backend.renderedUnlocked ? "this account is unlocked: no password"
                : backend.renderedCollects === "nothing" ? "confirm on the device when it asks"
                : backend.renderedCollects === "pin" ? "asks for the card's PIN"
                : "asks for the account's password"
        return "Signer: " + backend.renderedSigner + " — " + how
    }

    // Every signer holding the account, ranked by the manager. With more than one, the person picks.
    readonly property var holders: {
        try { return JSON.parse(backend ? backend.renderedSignersJson : "[]") } catch (e) { return [] }
    }
    readonly property bool choosing: showing && holders.length > 1 && backend.renderedSigning !== true
    function holderName(h) {
        if (h.transport === "keystore") return "This device (Keystore)"
        if (h.transport === "reader") return "Keycard · reader"
        if (h.transport === "usb") {
            var named = { keycard_shell: "Keycard Shell", ledger: "Ledger", trezor: "Trezor" }
            return (named[h.kind] || h.model || h.signer) + " · USB"
        }
        if (h.transport === "qr") return h.model && h.model !== "QR wallet" ? "QR · " + h.model : "QR wallet"
        return h.model || h.signer
    }
    function holderState(h) {
        return h.presence === "local" ? "ready" : h.presence === "connected" ? "connected"
             : h.presence === "absent" ? "not connected" : ""
    }
    function holderHow(h) {
        if (h.canTake !== true) return h.why || "It can't sign this request."
        if (h.presence === "absent")
            return h.transport === "reader" ? "Insert the card in a reader to sign with it." : "Connect it to sign with it."
        if (h.signer === backend.renderedSigner && backend.renderedUnlocked) return "This account is unlocked: no password."
        if (h.collects === "password") return "Asks for the account's password."
        if (h.collects === "pin") return "Asks for the card's PIN."
        if (h.transport === "qr") return "Shows the request as codes here, then reads its answer."
        return h.kind === "keycard_shell" ? "Confirm on the Shell when it asks." : "Confirm on the device when it asks."
    }

    component Section: Rectangle {
        id: sec
        property int number: 0
        property string heading: ""
        property string caption: ""
        default property alias content: body.data
        Layout.fillWidth: true
        color: "transparent"
        border.color: "#8888aa"
        border.width: 1
        radius: 4
        implicitHeight: inner.implicitHeight + 20

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            LogosText {
                Layout.fillWidth: true
                text: sec.number + ".  " + sec.heading
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.bold: true
            }
            LogosText {
                Layout.fillWidth: true
                visible: sec.caption !== ""
                text: sec.caption
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.italic: true
                opacity: 0.75
            }
            ColumnLayout {
                id: body
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 2
            }
        }
    }

    // A line of the manager's or the requester's text. Monospace and plain: see
    // the rendering rule at the top of this file.
    component Line: LogosText {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: "monospace"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            LogosText {
                text: root.ready ? backend.statusText : "Connecting…"
                textFormat: Text.PlainText
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                text: "Refresh"
                enabled: root.ready
                onClicked: backend.refresh()
            }
        }

        LogosText {
            visible: root.ready && backend.lastError !== ""
            Layout.fillWidth: true
            text: root.ready ? backend.lastError : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.palette.error
        }

        LogosTabBar {
            id: tabs
            objectName: "signerTabs"
            Layout.fillWidth: true
            // Not bound to root.page: a click assigns currentIndex and would break the binding.
            onCurrentIndexChanged: root.page = currentIndex
            LogosTabButton { text: root.queue.length > 0 ? "Requests (" + root.queue.length + ")" : "Requests" }
            LogosTabButton { text: "Wallets" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.page

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // ── the queue ───────────────────────────────────────────────────────
                LogosText {
                    visible: !root.showing
                    text: root.queue.length === 0
                          ? "No signing requests are waiting."
                          : "Select a request to review:"
                    textFormat: Text.PlainText
                }

                ListView {
                    visible: !root.showing
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: root.queue
                    delegate: LogosButton {
                        width: ListView.view.width
                        // Summary only — the queue never carries leg detail.
                        text: (modelData.requester || "unknown") + " — " +
                              (modelData.purpose || "signature") + "  [" +
                              String(modelData.handle).substring(0, 12) + "]"
                        onClicked: backend.acknowledge(modelData.handle)
                    }
                }

                // ── signed without asking ───────────────────────────────────────────
                // Inside an unlock the person granted without confirmation: listed, so it is never unseen twice.
                LogosText {
                    objectName: "unattendedHeading"
                    visible: !root.showing && root.unattended.length > 0
                    text: "Signed without asking:"
                    textFormat: Text.PlainText
                    font.bold: true
                }
                Repeater {
                    model: root.showing ? [] : root.unattended
                    delegate: LogosText {
                        objectName: "unattendedLine"
                        Layout.fillWidth: true
                        text: (modelData.requester || "unknown") + " — " + modelData.account
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                }

                // ── the request under review ────────────────────────────────────────
                //
                // Three sections, in this order and never merged: who is asking and what THEY
                // say it is for; what is actually signed; and what this signer makes of that.
                // The first is requester-authored, the second is the manager's, the third is
                // this backend's — and a human has to be able to tell them apart at a glance,
                // because the whole class of attack here is text that looks like it came from
                // somewhere more trustworthy than it did.
                ColumnLayout {
                    visible: root.showing
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        ColumnLayout {
                            width: parent.width
                            spacing: 10

                            Section {
                                objectName: "sectionRequester"
                                number: 1
                                // The name is the installed package's, never the requester's; the id always follows.
                                heading: "Requested by: " + (!root.ready ? ""
                                         : backend.renderedRequesterName
                                           ? backend.renderedRequesterName + " (" + backend.renderedRequester + ")"
                                           : backend.renderedRequester)
                                caption: "What that app says this is for. Its own words — this " +
                                         "signer cannot check any of it."

                                Repeater {
                                    model: root.ready ? backend.claimLines : []
                                    delegate: Line {
                                        objectName: "claimLine"
                                        text: modelData
                                    }
                                }
                                Line {
                                    objectName: "noClaimLine"
                                    visible: root.ready && backend.claimLines.length === 0
                                    text: "(it gave no reason)"
                                    font.family: "sans-serif"
                                    font.italic: true
                                }
                            }

                            Section {
                                objectName: "sectionSigned"
                                number: 2
                                heading: "What you are signing"
                                caption: "The signer manager's own reading of the request, shown " +
                                         "in full and never shortened. This is what the signature " +
                                         "will cover."

                                Repeater {
                                    model: root.ready ? backend.renderLines : []
                                    delegate: Line {
                                        objectName: "renderLine"
                                        text: modelData
                                    }
                                }
                            }

                            Section {
                                objectName: "sectionInterpretation"
                                number: 3
                                heading: "What this signer makes of section 2"
                                caption: "Decoded on this device from the lines above. Not part " +
                                         "of what is signed, and every line says how sure it is."

                                Repeater {
                                    // Named so the doc-test can assert the line COUNT: what this
                                    // layer must not do over a verified address is add anything,
                                    // and only a count can catch an absence.
                                    objectName: "interpretationLines"
                                    model: root.ready ? backend.interpretationLines : []
                                    delegate: Line {
                                        objectName: "interpretationLine"
                                        text: modelData
                                    }
                                }
                                Line {
                                    objectName: "noInterpretationLine"
                                    visible: root.ready && backend.interpretationLines.length === 0
                                    text: "(nothing could be decoded — which is normal for a " +
                                          "message, a digest, or a call this signer does not know)"
                                    font.family: "sans-serif"
                                    font.italic: true
                                }
                            }
                        }
                    }

                    LogosText {
                        objectName: "signerLine"
                        visible: root.signerLine !== "" && !root.choosing
                        Layout.fillWidth: true
                        text: root.signerLine
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }

                    // Which signer signs: the request and its commitment stay the same whichever is picked,
                    // so only the secret below changes, and a typed one is cleared.
                    ColumnLayout {
                        objectName: "signWith"
                        visible: root.choosing
                        Layout.fillWidth: true
                        spacing: 2

                        LogosText {
                            text: "Sign with"
                            textFormat: Text.PlainText
                            font.bold: true
                        }
                        Repeater {
                            model: root.choosing ? root.holders : []
                            delegate: RowLayout {
                                objectName: "signWithRow"
                                Layout.fillWidth: true
                                spacing: 8
                                enabled: modelData.canTake === true && modelData.presence !== "absent"
                                LogosRadioButton {
                                    objectName: "signWithChoice"
                                    // Not checkable: the manager's answer says who signs, not the click.
                                    checkable: false
                                    checked: modelData.signer === backend.renderedSigner
                                    text: root.holderName(modelData)
                                    // The reply is pending until it answers, and a pending reply is
                                    // always truthy: wait for the answer before clearing the secret.
                                    onClicked: logos.watch(backend.chooseSigner(backend.renderedHandle, modelData.signer),
                                                           function (chosen) { if (chosen) pw.text = "" })
                                }
                                LogosText {
                                    objectName: "signWithState"
                                    text: root.holderState(modelData)
                                    textFormat: Text.PlainText
                                    opacity: 0.75
                                }
                                LogosText {
                                    objectName: "signWithHow"
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    text: root.holderHow(modelData)
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                    color: Theme.palette.textSecondary
                                }
                            }
                        }
                    }

                    LogosText {
                        objectName: "deviceWaiting"
                        visible: root.showing && backend.renderedSigning === true && !root.qrDrawing
                                 && root.qr.in_window !== true
                        Layout.fillWidth: true
                        text: "Approved here. Now confirm on the device: this request stays until it answers."
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Theme.palette.textSecondary
                    }

                    LogosText {
                        objectName: "qrInWindow"
                        visible: root.showing && backend.renderedSigning === true && root.qr.in_window === true
                        Layout.fillWidth: true
                        text: "Approved here. Continue in the Logos QR window: it showed this request before this app could."
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Theme.palette.textSecondary
                    }

                    ColumnLayout {
                        objectName: "qrPanel"
                        visible: root.qrDrawing
                        Layout.fillWidth: true
                        spacing: 8

                        LogosText {
                            objectName: "qrHint"
                            Layout.fillWidth: true
                            text: root.qr.hint || ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                        }

                        // Dark modules on white whatever the theme, with the quiet zone a reader needs, and
                        // whole pixels a module so the edges stay sharp.
                        Canvas {
                            id: qrCanvas
                            objectName: "qrCode"
                            visible: root.qr.step === "show" && root.qrFrames.length > 0
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 420
                            Layout.preferredHeight: 420
                            property var frame: root.qrFrames.length > 0
                                                ? root.qrFrames[root.qrIndex % root.qrFrames.length] : null
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
                                for (var y = 0; y < frame.size; y++) {
                                    for (var x = 0; x < frame.size; x++) {
                                        if (frame.bits.charAt(y * frame.size + x) === "1")
                                            ctx.fillRect(off + x * m, off + y * m, m, m)
                                    }
                                }
                            }
                        }

                        LogosText {
                            objectName: "qrCamera"
                            visible: root.qr.step === "scan"
                            Layout.fillWidth: true
                            text: root.qr.seeing === true
                                  ? "A code is in view: hold it steady."
                                  : "No code in view yet: hold the wallet's answer up to the camera."
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                        }

                        LogosText {
                            objectName: "qrProgress"
                            visible: (root.qr.expected || 0) > 0
                            text: "Read " + (root.qr.received || 0) + " of " + (root.qr.expected || 0) + " parts"
                            textFormat: Text.PlainText
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            LogosButton {
                                objectName: "qrStepButton"
                                visible: (root.qr.label || "") !== ""
                                text: root.qr.label || ""
                                onClicked: backend.qrPress()
                            }
                            Item { Layout.fillWidth: true }
                            LogosButton {
                                objectName: "qrCancelButton"
                                text: "Cancel"
                                onClicked: backend.qrCancel()
                            }
                        }
                    }

                    LogosTextField {
                        id: pw
                        // Addressable by name: the doc-test harness locates fields with
                        // find_by "objectName", and a type name is not stable (QML
                        // decorates it, e.g. LogosTextField_QMLTYPE_18).
                        objectName: "vaultPasswordField"
                        visible: root.needsSecret
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        placeholderText: root.showing && backend.renderedCollects === "pin" ? "Card PIN" : "Vault password"

                        // Mask every character immediately. Qt's default reveals the
                        // last character typed for a second, which is exactly the
                        // character an onlooker needs. `passwordMaskDelay` lives on the
                        // inner TextInput -- LogosTextField does not re-expose it, but
                        // it does expose the input itself as a readonly alias, so set
                        // it there. Assigning it on the control fails to compile with
                        // "Cannot assign to non-existent property", which takes the
                        // WHOLE view down: a QML compile error means the plugin never
                        // renders at all.
                        Component.onCompleted: textInput.passwordMaskDelay = 0
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.needsSecret && backend.renderedCollects === "password" && backend.renderedAccount !== ""
                        LogosButton {
                            objectName: "signerUnlockLink"
                            text: "Unlock in the keys app…"
                            onClicked: root.unlockInKeysApp()
                        }
                        LogosText {
                            objectName: "unlockNote"
                            visible: root.unlockNote !== ""
                            Layout.fillWidth: true
                            text: root.unlockNote
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: Theme.palette.textSecondary
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        LogosButton {
                            objectName: "signerRejectButton"
                            text: "Reject"
                            onClicked: { backend.reject(backend.renderedHandle); pw.text = "" }
                        }
                        LogosButton {
                            objectName: "signerBackButton"
                            text: "Back"
                            // Read the handle BEFORE dismissing, which clears it. Walking away
                            // without deciding leaves the request queued, so the requester is told
                            // the same thing the user just did: not now.
                            onClicked: {
                                // A QR wallet's codes are drawn only here: leaving stops showing and reading
                                // them, and so cancels its signature, rather than leave the camera waiting.
                                if (root.qrDrawing) backend.qrCancel()
                                root.answerIntent(backend.renderedHandle, false, "cancelled")
                                backend.dismiss()
                                pw.text = ""
                            }
                        }
                        Item { Layout.fillWidth: true }
                        LogosButton {
                            id: approveBtn
                            objectName: "signerApproveButton"
                            // The dwell flag is owned by C++, so editing this binding
                            // cannot shorten it; the backend refuses early approvals
                            // regardless of what the view believes.
                            enabled: root.ready && backend.dwellElapsed && (!root.needsSecret || pw.text.length > 0)
                                     && backend.renderedSigning !== true
                            text: backend.dwellElapsed ? "Approve" : "Reading…"
                            onClicked: {
                                backend.approve(backend.renderedHandle, backend.renderedBundleId,
                                                root.needsSecret ? pw.text : "")
                                pw.text = ""
                            }
                        }
                    }
                }
            }

            WalletsView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                backend: root.ready ? root.backend : null
                onUnlock: function (seed, openHandle) { root.openUnlock(seed, openHandle) }
                onRule: function (seed) { root.openRule(seed, "rule") }
                onKeys: function (seed) { root.openRule(seed, "keys") }
            }
        }
    }

    // ── sheets over the view ────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: unlockSheet.visible || ruleSheet.visible
        color: "#80000000"
        MouseArea { anchors.fill: parent }
    }
    UnlockSheet {
        id: unlockSheet
        visible: root.unlockSeed !== ""
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 640)
        height: Math.min(parent.height - 32, implicitHeight)
        backend: root.ready ? root.backend : null
        seed: root.unlockSeed
        openHandle: root.unlockOpen
        onClosed: root.closeUnlock(false)
    }
    RuleSheet {
        id: ruleSheet
        visible: root.ruleSeed !== ""
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 640)
        height: Math.min(parent.height - 32, implicitHeight)
        backend: root.ready ? root.backend : null
        seed: root.ruleSeed
        mode: root.ruleMode
        onClosed: root.ruleSeed = ""
    }
}
