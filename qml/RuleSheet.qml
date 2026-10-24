import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// A wallet's rule, or new keys for it. Each rule says what it gains and what it gives up, so the
// convenient choice is always there and never the silent default.
Rectangle {
    id: sheet
    objectName: "ruleSheet"
    property var backend
    property string seed: ""
    // `rule` to choose how the wallet unlocks, `keys` for new keys.
    property string mode: "rule"
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
    readonly property var passwords: settings.passwords || []
    readonly property bool keystoreOnly: {
        var hs = wallet ? wallet.holders || [] : []
        return hs.length > 0 && hs.every(function (h) { return h.kind === "keystore" })
    }
    readonly property string deviceWord: keystoreOnly ? "its keystore password" : "the device"

    // The rules on offer. A wallet whose holders give no unlock key takes a password alone.
    readonly property var choices: wallet && wallet.device ? [
        { key: "device", label: keystoreOnly ? "Its keystore password only" : "The device only",
          gain: keystoreOnly ? "Nothing more to remember: the password you sign with unlocks it."
                             : "Nothing to remember: any holder of this seed unlocks it, a card restored from the phrase too.",
          giveUp: "Whoever has " + deviceWord + " and this computer sees this wallet." },
        { key: "and", label: (keystoreOnly ? "Its keystore password" : "The device") + " and a password",
          gain: "A stolen device alone doesn't show this wallet on this computer.",
          giveUp: "Forget the password and this wallet's data here is lost: you add the wallet again." },
        { key: "or", label: (keystoreOnly ? "Its keystore password" : "The device") + ", or a password alone",
          gain: "You can unlock it without " + deviceWord + ".",
          giveUp: "Whoever guesses the password on this computer sees this wallet." },
        { key: "always", label: "Always unlocked",
          gain: "Nothing to unlock: its accounts show from the moment Basecamp starts, and Lock leaves it open.",
          giveUp: "No protection: anyone with this computer's files reads this wallet's data here. Protecting it again later gives it new keys." }
    ] : [
        { key: "password", label: "A password",
          gain: "The wallet's accounts are kept here between sessions.",
          giveUp: "Forget the password and this wallet's data here is lost: you add the wallet again." },
        { key: "always", label: "Always unlocked",
          gain: "Nothing to unlock: its accounts show from the moment Basecamp starts, and Lock leaves it open.",
          giveUp: "No protection: anyone with this computer's files reads this wallet's data here. Protecting it again later gives it new keys." }
    ]
    property int choice: 0
    // An existing password's id, or `new`.
    property string passwordId: ""
    // Start from the wallet's rule as it is.
    function reset() {
        inputs.clear()
        passwordId = ""
        var ws = currentWays
        var and = ws.some(function (w) { return w.length === 2 && w.indexOf("device") >= 0 })
        var device = ws.some(function (w) { return w.length === 1 && w[0] === "device" })
        var alone = ws.some(function (w) { return w.length === 1 && w[0].indexOf("password:") === 0 })
        var always = ws.some(function (w) { return w.length === 0 })
        choice = always ? choices.length - 1 : !(wallet && wallet.device) ? 0 : and ? 1 : device && alone ? 2 : 0
        var pw = [].concat.apply([], ws).filter(function (f) { return f.indexOf("password:") === 0 })
        if (pw.length > 0) passwordId = pw[0].substring("password:".length)
    }
    readonly property var current: choices.length > choice ? choices[choice] : null
    readonly property bool needsPassword: current !== null && current.key !== "device" && current.key !== "always"
    readonly property string chosenPassword: !needsPassword ? "" : passwordId !== "" ? passwordId
                                           : passwords.length > 0 ? passwords[0].id : "new"

    function waysFor(key, pid) {
        var p = "password:" + pid
        if (key === "device") return [["device"]]
        if (key === "always") return [[]]
        if (key === "and") return [["device", p]]
        if (key === "or") return [["device"], [p]]
        return [[p]]
    }
    function sameWay(a, b) {
        return JSON.stringify(a.slice().sort()) === JSON.stringify(b.slice().sort())
    }
    function labelOf(f) {
        return f.kind === "device" ? "device" : "password:" + f.id
    }
    // The wallet's ways now, as factor labels.
    readonly property var currentWays: wallet ? (wallet.ways || []).map(function (w) { return w.factors.map(sheet.labelOf) }) : []
    // A way the new rule adds that takes the device needs the device again.
    readonly property bool newDeviceWay: {
        if (mode === "keys") return currentWays.some(function (w) { return w.indexOf("device") >= 0 })
        if (current === null) return false
        var next = waysFor(current.key, chosenPassword)
        return next.some(function (w) {
            return w.indexOf("device") >= 0 && !sheet.currentWays.some(function (c) { return sheet.sameWay(c, w) })
        })
    }
    // New keys wrap every way again, so each password in the rule is typed.
    readonly property var stepPasswords: {
        if (mode === "keys") {
            var seen = {}, out = []
            var ws = wallet ? wallet.ways || [] : []
            for (var i = 0; i < ws.length; i++)
                for (var j = 0; j < ws[i].factors.length; j++) {
                    var f = ws[i].factors[j]
                    if (f.kind === "password" && !seen[f.id]) { seen[f.id] = true; out.push({ id: f.id, name: f.name || "?" }) }
                }
            return out
        }
        if (!needsPassword || chosenPassword === "new") return []
        for (var k = 0; k < passwords.length; k++)
            if (passwords[k].id === chosenPassword) return [{ id: passwords[k].id, name: passwords[k].name }]
        return []
    }
    readonly property bool newPasswordReady: chosenPassword !== "new"
        || (newName.text.trim().length > 0 && newPassword.text.length >= 8 && newPassword.text === newAgain.text)

    function apply() {
        var holder = inputs.holder ? inputs.holder.signer : ""
        var secret = sheet.newDeviceWay ? inputs.secret : ""
        if (mode === "keys") {
            backend.changeKeys(seed, nextIndex.checked, sheet.newDeviceWay ? holder : "", secret, inputs.passwordsJson())
            inputs.clear()
            return
        }
        var run = function (pid, typed) {
            backend.setRule(seed, JSON.stringify(sheet.waysFor(sheet.current.key, pid)),
                            sheet.newDeviceWay ? holder : "", secret, typed)
            inputs.clear()
        }
        if (needsPassword && chosenPassword === "new") {
            var name = newName.text.trim(), pw = newPassword.text
            newPassword.text = ""
            newAgain.text = ""
            logos.watch(backend.createPassword(name, pw), function (id) {
                if (!id) return
                var typed = {}
                typed[id] = pw
                run(id, JSON.stringify(typed))
                pw = ""
            })
            return
        }
        run(chosenPassword, inputs.passwordsJson())
    }

    readonly property var step: parse(backend ? backend.unlockJson : "{}", ({}))
    readonly property bool working: step.seed === seed && step.state === "device"

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        LogosText {
            objectName: "ruleTitle"
            Layout.fillWidth: true
            text: (sheet.mode === "keys" ? "New keys for " : "How ") + (sheet.wallet ? sheet.wallet.privateName || sheet.wallet.name : "")
                  + (sheet.mode === "keys" ? "" : " unlocks")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.bold: true
        }

        // ── the rule ───────────────────────────────────────────────────────
        Repeater {
            model: sheet.mode === "rule" ? sheet.choices : []
            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                LogosRadioButton {
                    objectName: "ruleChoice"
                    checkable: false
                    checked: index === sheet.choice
                    text: modelData.label
                    onClicked: sheet.choice = index
                }
                LogosText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 28
                    text: "Gains: " + modelData.gain
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.palette.textSecondary
                }
                LogosText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 28
                    text: "Gives up: " + modelData.giveUp
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.palette.textSecondary
                }
            }
        }

        // ── which password ─────────────────────────────────────────────────
        ColumnLayout {
            visible: sheet.mode === "rule" && sheet.needsPassword
            Layout.fillWidth: true
            spacing: 4
            LogosText {
                text: "Password"
                textFormat: Text.PlainText
                font.bold: true
            }
            Repeater {
                model: sheet.passwords
                delegate: LogosRadioButton {
                    objectName: "rulePassword"
                    checkable: false
                    checked: sheet.chosenPassword === modelData.id
                    text: "“" + modelData.name + "”" + (modelData.wallets.length > 0
                          ? " · unlocks " + modelData.wallets.length + " wallet" + (modelData.wallets.length === 1 ? "" : "s") : "")
                    onClicked: sheet.passwordId = modelData.id
                }
            }
            LogosRadioButton {
                objectName: "ruleNewPassword"
                checkable: false
                checked: sheet.chosenPassword === "new"
                text: "A new password"
                onClicked: sheet.passwordId = "new"
            }
            LogosTextField {
                id: newName
                objectName: "ruleNewPasswordName"
                visible: sheet.chosenPassword === "new"
                Layout.fillWidth: true
                placeholderText: "Its name, shown when you unlock (e.g. Home)"
            }
            LogosTextField {
                id: newPassword
                objectName: "ruleNewPasswordField"
                visible: sheet.chosenPassword === "new"
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "The password, 8 characters or more"
                Component.onCompleted: textInput.passwordMaskDelay = 0
            }
            LogosTextField {
                id: newAgain
                objectName: "ruleNewPasswordAgain"
                visible: sheet.chosenPassword === "new"
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "The password again"
                Component.onCompleted: textInput.passwordMaskDelay = 0
            }
        }

        // ── new keys ───────────────────────────────────────────────────────
        LogosText {
            visible: sheet.mode === "keys"
            Layout.fillWidth: true
            text: "Every app re-encrypts its data for this wallet under new keys the next time it reads it. "
                  + "Use this if a key may have been seen."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
        LogosCheckbox {
            id: nextIndex
            objectName: "keysNextIndex"
            visible: sheet.mode === "keys" && sheet.newDeviceWay
            text: "Also move to the device's next unlock key (if a QR wallet's answer may have been photographed)"
        }

        LogosText {
            visible: sheet.newDeviceWay || sheet.stepPasswords.length > 0
            Layout.fillWidth: true
            text: sheet.mode === "keys" ? "To wrap the new keys, this needs:" : "To set it, this needs:"
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.bold: true
        }
        StepInputs {
            id: inputs
            Layout.fillWidth: true
            wallet: sheet.wallet
            needsDevice: sheet.newDeviceWay
            passwords: sheet.stepPasswords
        }
        LogosText {
            objectName: "ruleWorking"
            visible: sheet.working
            Layout.fillWidth: true
            text: "Confirm on the device."
            textFormat: Text.PlainText
        }
        QrCodes {
            visible: sheet.working && sheet.backend !== null && sheet.parse(sheet.backend.qrJson, ({})).active === true
            Layout.fillWidth: true
            backend: sheet.backend
        }
        LogosText {
            visible: !!(sheet.backend && sheet.backend.walletError)
            Layout.fillWidth: true
            text: (sheet.backend && sheet.backend.walletError) || ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.palette.error
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            LogosButton {
                objectName: "ruleClose"
                text: sheet.working ? "Cancel" : "Close"
                onClicked: {
                    if (sheet.working) sheet.backend.cancelUnlock()
                    inputs.clear()
                    sheet.closed()
                }
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                objectName: "ruleApply"
                enabled: !sheet.working && inputs.complete && (sheet.mode === "keys" || (sheet.current !== null && sheet.newPasswordReady))
                text: sheet.mode === "keys" ? "Make new keys" : "Use this rule"
                onClicked: sheet.apply()
            }
        }
    }
}
