import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// Unlocking one wallet, once, for every app. It offers the wallet's ways in and asks for what the
// chosen one takes. When an app asked to open the wallet, that request is shown here beside it,
// in the signer manager's words, and opening it is the person's consent.
Rectangle {
    id: sheet
    objectName: "unlockSheet"
    property var backend
    property string seed: ""
    // The open that brought the person here, if any.
    property string openHandle: ""
    // How many more wallets the ask that brought the person here unlocks after this one.
    property int after: 0
    signal closed()

    color: Theme.palette.background
    border.color: "#8888aa"
    border.width: 1
    radius: 6
    implicitHeight: body.implicitHeight + 32

    function parse(raw, empty) {
        try { return JSON.parse(raw) } catch (e) { return empty }
    }
    readonly property var settings: parse(backend ? backend.walletsJson : "{}", ({}))
    readonly property var wallet: {
        var ws = settings.wallets || []
        for (var i = 0; i < ws.length; i++)
            if (ws[i].seed === seed) return ws[i]
        return null
    }
    readonly property string title: wallet ? (wallet.privateName || wallet.name) : ""
    readonly property var step: parse(backend ? backend.unlockJson : "{}", ({}))
    readonly property bool mine: step.seed === seed
    readonly property bool working: mine && step.state === "device"
    readonly property bool retyping: mine && step.state === "needs_password"
    readonly property bool failed: mine && step.state === "failed"
    readonly property bool unlocked: wallet !== null && wallet.locked === false
    readonly property var open: {
        var o = parse(backend ? backend.openJson : "{}", ({}))
        return o.handle && o.handle === openHandle ? o : null
    }

    property int wayIndex: 0
    onSeedChanged: { wayIndex = 0; inputs.clear() }
    onOpenHandleChanged: if (openHandle !== "" && backend) backend.showOpen(openHandle)
    readonly property var ways: wallet ? wallet.ways || [] : []
    readonly property var way: ways.length > wayIndex ? ways[wayIndex] : null
    readonly property bool takesDevice: way !== null && way.factors.some(function (f) { return f.kind === "device" })
    readonly property var wayPasswords: way === null ? [] : way.factors
        .filter(function (f) { return f.kind === "password" })
        .map(function (f) { return { id: f.id, name: f.name || "?" } })

    function wayText(w) {
        var parts = w.factors.map(function (f) {
            return f.kind === "device" ? (sheet.keystoreOnly() ? "its keystore password" : "the device")
                                       : "the password “" + (f.name || "?") + "”"
        })
        return parts.join(" and ")
    }
    // A keystore wallet's device is the keystore: its own password unlocks it.
    function keystoreOnly() {
        var hs = wallet ? wallet.holders || [] : []
        return hs.length > 0 && hs.every(function (h) { return h.kind === "keystore" })
    }
    function workingText() {
        var kind = ""
        var hs = wallet ? wallet.holders || [] : []
        for (var i = 0; i < hs.length; i++)
            if (hs[i].signer === step.holder) kind = hs[i].kind
        if (kind === "keycard_shell") return "Confirm on the Shell: it asks to unlock this wallet."
        if (kind === "keycard") return "The card is working: keep it in the reader."
        if (kind === "qr") return "Scan these codes with the QR wallet, then show its answer to the camera."
        if (step.step === "confirm_on_device") return "Confirm on the device."
        return "Working…"
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        LogosText {
            objectName: "unlockTitle"
            Layout.fillWidth: true
            text: (sheet.unlocked ? "Unlocked: " : "Unlock ") + sheet.title
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.bold: true
        }
        LogosText {
            objectName: "unlockAfter"
            visible: sheet.after > 0
            Layout.fillWidth: true
            text: sheet.after === 1 ? "Then 1 more wallet." : "Then " + sheet.after + " more wallets."
            color: Theme.palette.textSecondary
        }
        LogosText {
            Layout.fillWidth: true
            text: sheet.unlocked
                  ? "Every app can use this wallet until you lock it or quit."
                  : "Unlocking it here unlocks it for every app until you lock it or quit."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.palette.textSecondary
        }
        LogosText {
            objectName: "unlockNoWay"
            visible: !sheet.unlocked && sheet.wallet !== null && sheet.ways.length === 0
            Layout.fillWidth: true
            text: "This wallet has no way in yet: it was added this session and needs a password before it can be unlocked again."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }

        // ── how ─────────────────────────────────────────────────────────────
        ColumnLayout {
            visible: !sheet.unlocked && !sheet.working && !sheet.retyping
            Layout.fillWidth: true
            spacing: 4
            LogosText {
                visible: sheet.ways.length > 1
                text: "Unlock with"
                textFormat: Text.PlainText
                font.bold: true
            }
            Repeater {
                model: sheet.ways.length > 1 ? sheet.ways : []
                delegate: LogosRadioButton {
                    objectName: "unlockWay"
                    checkable: false
                    checked: index === sheet.wayIndex
                    text: sheet.wayText(modelData)
                    onClicked: { sheet.wayIndex = index; inputs.clear() }
                }
            }
            LogosText {
                visible: sheet.ways.length === 1
                Layout.fillWidth: true
                text: sheet.way ? "Unlocks with " + sheet.wayText(sheet.way) + "." : ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            StepInputs {
                id: inputs
                Layout.fillWidth: true
                wallet: sheet.wallet
                needsDevice: sheet.takesDevice
                passwords: sheet.wayPasswords
            }
        }

        // ── the device at work ──────────────────────────────────────────────
        LogosText {
            objectName: "unlockWorking"
            visible: sheet.working
            Layout.fillWidth: true
            text: sheet.workingText()
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
        QrCodes {
            visible: sheet.working && sheet.backend !== null && sheet.parse(sheet.backend.qrJson, ({})).active === true
            Layout.fillWidth: true
            backend: sheet.backend
        }

        // ── the device answered, a password didn't ──────────────────────────
        LogosText {
            objectName: "unlockRetype"
            visible: sheet.retyping
            Layout.fillWidth: true
            text: (sheet.step.error || "A password is not correct.") + " The device has answered: type the password again."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.palette.error
        }
        StepInputs {
            id: retype
            visible: sheet.retyping
            Layout.fillWidth: true
            wallet: sheet.wallet
            needsDevice: false
            passwords: sheet.retyping ? sheet.wayPasswords : []
        }

        LogosText {
            objectName: "unlockFailed"
            visible: sheet.failed && !sheet.unlocked
            Layout.fillWidth: true
            text: sheet.step.error || "The wallet was not unlocked."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.palette.error
        }
        LogosText {
            objectName: "unlockError"
            visible: !!(sheet.backend && sheet.backend.walletError)
            Layout.fillWidth: true
            text: (sheet.backend && sheet.backend.walletError) || ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.palette.error
        }

        // ── an app asked to open it ─────────────────────────────────────────
        ColumnLayout {
            objectName: "unlockOpen"
            visible: sheet.open !== null
            Layout.fillWidth: true
            spacing: 2
            LogosText {
                text: "An app asks to open this wallet"
                textFormat: Text.PlainText
                font.bold: true
            }
            Repeater {
                model: sheet.open ? sheet.open.lines || [] : []
                delegate: LogosText {
                    objectName: "unlockOpenLine"
                    Layout.fillWidth: true
                    text: modelData
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    font.family: "monospace"
                }
            }
            LogosText {
                visible: !sheet.unlocked
                Layout.fillWidth: true
                text: "Unlock the wallet first: then you can open it for that app."
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.palette.textSecondary
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                LogosButton {
                    objectName: "unlockOpenRefuse"
                    text: "Refuse"
                    onClicked: sheet.backend.rejectOpen(sheet.open.handle)
                }
                Item { Layout.fillWidth: true }
                LogosButton {
                    objectName: "unlockOpenConsent"
                    enabled: sheet.unlocked
                    text: "Open it for that app"
                    onClicked: sheet.backend.consentOpen(sheet.open.handle, sheet.open.bundle_id, "")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            LogosButton {
                objectName: "unlockClose"
                text: sheet.working ? "Cancel" : "Close"
                onClicked: {
                    if (sheet.working || sheet.retyping) sheet.backend.cancelUnlock()
                    inputs.clear()
                    retype.clear()
                    sheet.closed()
                }
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                objectName: "unlockRetry"
                visible: sheet.retyping
                enabled: retype.complete
                text: "Try again"
                onClicked: { sheet.backend.retryUnlock(retype.passwordsJson()); retype.clear() }
            }
            LogosButton {
                objectName: "unlockButton"
                visible: !sheet.unlocked && !sheet.working && !sheet.retyping && sheet.way !== null
                enabled: inputs.complete
                text: sheet.takesDevice && inputs.asks === "" ? "Unlock with the device" : "Unlock"
                onClicked: {
                    var holder = sheet.takesDevice && inputs.holder ? inputs.holder.signer : ""
                    sheet.backend.unlockWallet(sheet.seed, sheet.way.id, holder,
                                               sheet.takesDevice ? inputs.secret : "", inputs.passwordsJson())
                    inputs.clear()
                }
            }
        }
    }
}
