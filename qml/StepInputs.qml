import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// What a step on a wallet takes: which of its holders to ask when it takes the device, that
// holder's PIN or password, and each named password. Used by unlocking, a rule change and new
// keys alike. Nothing typed here is kept once `clear()` is called.
ColumnLayout {
    id: inputs
    // The wallet, as `wallet_settings` lists it.
    property var wallet: null
    property bool needsDevice: false
    // `[{ id, name }]`: the named passwords the step takes.
    property var passwords: []
    property string holderName: ""
    spacing: 6

    readonly property var holders: wallet ? wallet.holders || [] : []
    readonly property var holder: {
        for (var i = 0; i < holders.length; i++)
            if (holders[i].signer === holderName) return holders[i]
        return holders.length > 0 ? holders[0] : null
    }
    // What the holder asks for: `password` (the keystore), `pin` (a card), or nothing here.
    readonly property string asks: !holder ? "" : holder.kind === "keystore" ? "password"
                                 : holder.kind === "keycard" ? "pin" : ""
    readonly property string secret: secretField.text
    property var typed: ({})

    function holderLabel(h) {
        var named = { keystore: "This device (Keystore)", keycard: "Keycard · reader",
                      keycard_shell: "Keycard Shell · USB", qr: "QR wallet" }
        return named[h.kind] || h.signer
    }
    function holderHow(h) {
        if (h.kind === "keystore") return "Asks for the wallet's keystore password."
        if (h.kind === "keycard") return "Asks for the card's PIN."
        if (h.kind === "keycard_shell") return "Confirm on the Shell when it asks."
        if (h.kind === "qr") return "Shows a request as codes here, then reads the wallet's answer."
        return "Confirm on the device when it asks."
    }
    // `{ id: password }` for the step's passwords, as the backend takes them.
    function passwordsJson() {
        var out = {}
        for (var i = 0; i < passwords.length; i++)
            if (inputs.typed[passwords[i].id]) out[passwords[i].id] = inputs.typed[passwords[i].id]
        return JSON.stringify(out)
    }
    // Everything the step takes is there.
    readonly property bool complete: {
        if (needsDevice && asks !== "" && secretField.text.length === 0) return false
        for (var i = 0; i < passwords.length; i++)
            if (!(typed[passwords[i].id] || "").length) return false
        return true
    }
    function clear() {
        secretField.text = ""
        inputs.typed = ({})
        for (var i = 0; i < passwordFields.count; i++) {
            var f = passwordFields.itemAt(i)
            if (f) f.text = ""
        }
    }

    LogosText {
        visible: inputs.needsDevice && inputs.holders.length > 1
        text: "Ask"
        textFormat: Text.PlainText
        font.bold: true
    }
    Repeater {
        model: inputs.needsDevice && inputs.holders.length > 1 ? inputs.holders : []
        delegate: RowLayout {
            Layout.fillWidth: true
            spacing: 8
            LogosRadioButton {
                objectName: "stepHolder"
                checkable: false
                checked: inputs.holder && modelData.signer === inputs.holder.signer
                text: inputs.holderLabel(modelData)
                onClicked: { inputs.holderName = modelData.signer; secretField.text = "" }
            }
            LogosText {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                text: inputs.holderHow(modelData)
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.palette.textSecondary
            }
        }
    }
    // One holder: the same row as the choice above, without the choice.
    RowLayout {
        visible: inputs.needsDevice && inputs.holders.length === 1 && inputs.holder !== null
        Layout.fillWidth: true
        spacing: 8
        LogosText {
            objectName: "stepHolderLabel"
            text: inputs.holder ? inputs.holderLabel(inputs.holder) : ""
            textFormat: Text.PlainText
        }
        LogosText {
            objectName: "stepHolderHow"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            text: inputs.holder ? inputs.holderHow(inputs.holder) : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.palette.textSecondary
        }
    }
    LogosTextField {
        id: secretField
        objectName: "stepSecretField"
        visible: inputs.needsDevice && inputs.asks !== ""
        Layout.fillWidth: true
        echoMode: TextInput.Password
        placeholderText: inputs.asks === "pin" ? "Card PIN" : "Keystore password"
        Component.onCompleted: textInput.passwordMaskDelay = 0
    }
    Repeater {
        id: passwordFields
        model: inputs.passwords
        delegate: LogosTextField {
            objectName: "stepPasswordField"
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: "Password “" + modelData.name + "”"
            Component.onCompleted: textInput.passwordMaskDelay = 0
            onTextChanged: {
                var t = Object.assign({}, inputs.typed)
                t[modelData.id] = text
                inputs.typed = t
            }
        }
    }
}
