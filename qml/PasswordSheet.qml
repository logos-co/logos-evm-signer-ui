import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

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
    // Called by the host when the sheet opens, so it never reopens pre-filled or mid-wait.
    function reset() { awaiting = false; clear() }

    readonly property bool canSubmit:
          mode === "add"    ? (addName.text.trim().length > 0 && addPw.text.length >= 8 && addPw.text === addPw2.text)
        : mode === "rename" ? (renameName.text.trim().length > 0)
        : mode === "change" ? (oldPw.text.length > 0 && newPw.text.length >= 8 && newPw.text === newPw2.text)
        : mode === "remove" ? (pwWallets === 0)
        : false

    // add/rename/remove call refreshWallets, so the wallet settings change after the op: close on
    // that change when there is no error, and stay open showing the error otherwise. change has no
    // settings delta, so it waits for changePassword's own answer instead (logos.watch).
    property bool awaiting: false
    onSettingsChanged: {
        if (!sheet.awaiting || sheet.mode === "change") return
        sheet.awaiting = false
        if (sheet.backend && sheet.backend.walletError && sheet.backend.walletError.length > 0) return
        sheet.clear(); sheet.closed()
    }

    function submit() {
        if (!sheet.canSubmit) return
        sheet.awaiting = true
        if (sheet.mode === "add")
            sheet.backend.createPassword(addName.text, addPw.text)
        else if (sheet.mode === "rename")
            sheet.backend.renamePassword(sheet.pwId, renameName.text)
        else if (sheet.mode === "change") {
            // Close only once it worked; a wrong current password keeps the sheet open, its
            // error shown here (walletError), with the typed passwords cleared to retype.
            logos.watch(sheet.backend.changePassword(sheet.pwId, oldPw.text, newPw.text), function (ok) {
                sheet.awaiting = false
                if (ok) { sheet.clear(); sheet.closed() }
                else { oldPw.text = ""; newPw.text = ""; newPw2.text = "" }
            })
        } else if (sheet.mode === "remove")
            sheet.backend.removePassword(sheet.pwId)
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
            id: addPw2; visible: sheet.mode === "add"
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
            id: newPw2; visible: sheet.mode === "change"
            Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "New password again"
            Component.onCompleted: textInput.passwordMaskDelay = 0
        }

        LogosText {
            objectName: "passwordSheetError"
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
                objectName: "passwordSheetCancel"
                text: sheet.blocked ? "Close" : "Cancel"
                onClicked: { sheet.clear(); sheet.closed() }
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                objectName: "passwordSheetSubmit"
                // When removal is blocked there is nothing to do but close, so hide the action.
                visible: !sheet.blocked
                enabled: sheet.canSubmit
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
