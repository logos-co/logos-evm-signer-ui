import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "errors.js" as Errors

// Add, rename, change or remove a vault password, in a sheet over the Passwords tab. Matches the
// unlock and rule sheets: a title, a one-line explanation, the inputs, then Cancel and a primary
// action. `mode` selects which of the four it is; the host sets the target before showing it.
Rectangle {
    id: sheet
    objectName: "passwordSheet"
    property var backend
    property string mode: ""        // "" | add | rename | change | remove
    property string pwId: ""
    property string pwName: ""
    property int pwWallets: 0
    signal closed()

    color: Theme.palette.background
    border.color: "#8888aa"
    border.width: 1
    radius: 6
    implicitHeight: body.implicitHeight + 32

    function parse(raw, empty) { try { return JSON.parse(raw) } catch (e) { return empty } }
    readonly property var settings: parse(backend ? backend.walletsJson : "{}", ({}))
    readonly property int pwCount: (settings.passwords || []).length
    readonly property bool blocked: mode === "remove" && pwWallets > 0

    readonly property string titleText:
          mode === "add"    ? "Add a password"
        : mode === "rename" ? "Rename password"
        : mode === "change" ? "Change password"
        : mode === "remove" ? (blocked ? "Can’t remove this password yet" : "Remove password?")
        : ""
    readonly property string descText:
          mode === "add"
            ? "A password can unlock several wallets, as each wallet's rule says. Its name shows when you unlock. Use 8 characters or more."
        : mode === "rename"
            ? "The name shows when you unlock. This does not change the password itself."
        : mode === "change"
            ? "Set a new password for “" + pwName + "”. Wallets that use it keep working with the new one. Use 8 characters or more."
        : mode === "remove" && blocked
            ? "“" + pwName + "” unlocks " + pwWallets + " wallet" + (pwWallets === 1 ? "" : "s")
              + ". Change those wallets' unlock rules in the Wallets tab to another way in first. A wallet whose only way in is this password would otherwise have no way to unlock."
        : mode === "remove"
            ? "This removes “" + pwName + "” from this computer. It is not a wallet's unlock rule, so no wallet depends on it. This can't be undone."
        : ""

    function clear() {
        addName.text = ""; addPw.text = ""; addPw2.text = ""
        renameName.text = pwName
        oldPw.text = ""; newPw.text = ""; newPw2.text = ""
    }
    // Called by the host whenever the sheet shows or hides: it never reopens pre-filled, and what
    // was typed doesn't stay behind in hidden fields once it closes. An answer still on its way
    // for the sheet as it was is ignored.
    function reset() { awaiting = false; attempt++; error = ""; clear() }

    readonly property bool canSubmit:
          mode === "add"    ? (addName.text.trim().length > 0 && addPw.text.length >= 8 && addPw.text === addPw2.text)
        : mode === "rename" ? (renameName.text.trim().length > 0)
        : mode === "change" ? (oldPw.text.length > 0 && newPw.text.length >= 8 && newPw.text === newPw2.text)
        : mode === "remove" ? (pwWallets === 0)
        : false

    // Why the primary action is still off, once something is typed: the rules are otherwise
    // only in the description, and a button that stays grey says nothing.
    readonly property string hint: {
        if (mode === "add") {
            if (addPw.text.length > 0 && addPw.text.length < 8) return "At least 8 characters."
            if (addPw2.text.length > 0 && addPw2.text !== addPw.text) return "The two passwords don't match."
            if (addPw.text.length > 0 && addName.text.trim().length === 0) return "Give it a name."
        } else if (mode === "rename") {
            if (renameName.text.trim().length === 0) return "Give it a name."
        } else if (mode === "change") {
            if (newPw.text.length > 0 && newPw.text.length < 8) return "At least 8 characters."
            if (newPw2.text.length > 0 && newPw2.text !== newPw.text) return "The two new passwords don't match."
            if (newPw.text.length > 0 && oldPw.text.length === 0) return "Type the current password too."
        }
        return ""
    }

    // Every action waits for the backend's own answer. Only a success clears the fields and closes
    // the sheet; a failure keeps what was typed and shows why here: the backend's walletError, read
    // as this sheet's own call answers, never the live property other views share.
    property bool awaiting: false
    property int attempt: 0
    property string error: ""
    function answered(ok) {
        sheet.awaiting = false
        if (ok) { sheet.clear(); sheet.closed() }
        else sheet.error = Errors.human(sheet.backend ? sheet.backend.walletError : "") || "That did not work. Try again."
    }

    function submit() {
        if (!sheet.canSubmit || sheet.awaiting) return
        sheet.awaiting = true
        sheet.error = ""
        var mine = ++sheet.attempt
        var done = function (ok) { if (mine === sheet.attempt) sheet.answered(!!ok) }
        // The call itself failed (no answer from the backend): the sheet is usable again.
        var lost = function () {
            if (mine !== sheet.attempt) return
            sheet.awaiting = false
            sheet.error = "The Signer did not answer. Try again."
        }
        if (sheet.mode === "add")
            // The new password's id, or "" when it wasn't made.
            logos.watch(sheet.backend.createPassword(addName.text, addPw.text), function (id) { done(id && id.length > 0) }, lost)
        else if (sheet.mode === "rename")
            logos.watch(sheet.backend.renamePassword(sheet.pwId, renameName.text), done, lost)
        else if (sheet.mode === "change")
            logos.watch(sheet.backend.changePassword(sheet.pwId, oldPw.text, newPw.text), done, lost)
        else if (sheet.mode === "remove")
            logos.watch(sheet.backend.removePassword(sheet.pwId), done, lost)
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        LogosText {
            objectName: "passwordSheetTitle"
            Layout.fillWidth: true
            text: sheet.titleText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.pixelSize: Theme.typography.panelTitleText
            font.weight: Theme.typography.weightBold
        }
        LogosText {
            Layout.fillWidth: true
            text: sheet.descText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.palette.textSecondary
        }

        // add
        LogosTextField {
            id: addName; objectName: "passwordAddName"; visible: sheet.mode === "add"
            Layout.fillWidth: true; placeholderText: "Name (e.g. Home)"
        }
        LogosTextField {
            id: addPw; objectName: "passwordAddField"; visible: sheet.mode === "add"
            Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "Password, 8 characters or more"
            Component.onCompleted: textInput.passwordMaskDelay = 0
        }
        LogosTextField {
            id: addPw2; objectName: "passwordAddAgain"; visible: sheet.mode === "add"
            Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "Password again"
            Component.onCompleted: textInput.passwordMaskDelay = 0
        }

        // rename
        LogosTextField {
            id: renameName; objectName: "passwordRenameField"; visible: sheet.mode === "rename"
            Layout.fillWidth: true; placeholderText: "Name"
        }

        // change
        LogosTextField {
            id: oldPw; objectName: "passwordOld"; visible: sheet.mode === "change"
            Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "Current password"
            Component.onCompleted: textInput.passwordMaskDelay = 0
        }
        LogosTextField {
            id: newPw; objectName: "passwordNew"; visible: sheet.mode === "change"
            Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "New password, 8 characters or more"
            Component.onCompleted: textInput.passwordMaskDelay = 0
        }
        LogosTextField {
            id: newPw2; objectName: "passwordNewAgain"; visible: sheet.mode === "change"
            Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "New password again"
            Component.onCompleted: textInput.passwordMaskDelay = 0
        }

        LogosText {
            objectName: "passwordSheetHint"
            visible: sheet.hint !== ""
            Layout.fillWidth: true
            text: sheet.hint
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.palette.textSecondary
        }
        LogosText {
            objectName: "passwordSheetError"
            visible: sheet.error !== ""
            Layout.fillWidth: true
            text: sheet.error
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.palette.error
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            LogosButton {
                objectName: "passwordSheetCancel"
                text: sheet.blocked ? "Close" : "Cancel"
                onClicked: { sheet.reset(); sheet.closed() }
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                objectName: "passwordSheetSubmit"
                // When removal is blocked there is nothing to do but close, so hide the action.
                visible: !sheet.blocked
                enabled: sheet.canSubmit && !sheet.awaiting
                variant: LogosButton.Variant.Primary
                text: sheet.mode === "add" ? "Add password"
                    : sheet.mode === "rename" ? "Save"
                    : sheet.mode === "change" ? "Change it"
                    : "Remove"
                onClicked: sheet.submit()
            }
        }
    }
}
