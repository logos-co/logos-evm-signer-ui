import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// Every wallet, whichever signers hold it: its names, its holders, how it unlocks, its accounts
// once unlocked, and the apps waiting to open it. Device setup stays in each device's own app.
ColumnLayout {
    id: view
    objectName: "walletsView"
    property var backend
    signal unlock(string seed, string openHandle)
    signal rule(string seed)
    signal keys(string seed)
    spacing: 10

    function parse(raw, empty) {
        try { return JSON.parse(raw) } catch (e) { return empty }
    }
    readonly property var settings: parse(backend ? backend.walletsJson : "{}", ({}))
    readonly property var wallets: settings.wallets || []
    readonly property var passwords: settings.passwords || []
    readonly property var roster: parse(backend ? backend.rosterJson : "[]", [])
    readonly property var opens: parse(backend ? backend.opensJson : "[]", [])
    readonly property var shownOpen: parse(backend ? backend.openJson : "{}", ({}))
    readonly property bool anyUnlocked: wallets.some(function (w) { return !w.locked })

    function accountsOf(seed) { return roster.filter(function (a) { return a.seed === seed }) }
    function opensOf(seed) { return opens.filter(function (o) { return (o.seed || "") === seed }) }
    function holderLabel(h) {
        var named = { keystore: "Keystore", keycard: "Keycard", keycard_shell: "Keycard Shell", qr: "QR wallet" }
        return named[h.kind] || h.signer
    }
    function holdersText(w) {
        var seen = [], out = []
        for (var i = 0; i < (w.holders || []).length; i++) {
            var l = holderLabel(w.holders[i])
            if (seen.indexOf(l) < 0) { seen.push(l); out.push(l) }
        }
        return "Held by: " + out.join(", ")
    }
    function ruleText(w) {
        var keystore = (w.holders || []).length > 0 && w.holders.every(function (h) { return h.kind === "keystore" })
        var ways = (w.ways || []).map(function (way) {
            return way.factors.map(function (f) {
                return f.kind === "device" ? (keystore ? "its keystore password" : "the device")
                                           : "the password “" + (f.name || "?") + "”"
            }).join(" and ")
        })
        if (ways.length === 0) return "No way in yet: set a password, or it can't be unlocked after a restart."
        return "Unlocks with " + ways.join(", or ") + "."
    }
    // An account's own name, never its wallet's, then where it is: its address, or a Bitcoin
    // account's path and network, so mainnet and test accounts of one index tell apart.
    function accountLine(a, wallet) {
        var family = a.family === "evm" ? "Ethereum" : a.family === "bitcoin" ? "Bitcoin" : a.family === "bitcoin_taproot" ? "Bitcoin taproot" : a.family
        var own = a.label && a.label !== wallet ? a.label : ""
        var where = a.address || (a.path ? a.path + (a.chain === "test" ? " · test networks" : "") : a.key)
        return family + " · " + (own ? own + " · " : "") + where
    }

    property string editing: ""
    property string consentAccount: ""

    RowLayout {
        Layout.fillWidth: true
        LogosText {
            text: "Wallets"
            textFormat: Text.PlainText
            font.bold: true
        }
        Item { Layout.fillWidth: true }
        LogosButton {
            objectName: "lockAllButton"
            enabled: view.anyUnlocked
            text: "Lock all"
            onClicked: view.backend.lockWallets("[]")
        }
    }
    LogosText {
        objectName: "walletError"
        visible: !!(view.backend && view.backend.walletError)
        Layout.fillWidth: true
        text: (view.backend && view.backend.walletError) || ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.palette.error
    }
    LogosText {
        visible: view.wallets.length === 0
        Layout.fillWidth: true
        text: "No wallets yet. Add one in the keys app, the Keycard app or QR Wallets: it shows up here."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }

    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 10

            Repeater {
                model: view.wallets
                delegate: Rectangle {
                    id: card
                    objectName: "walletCard"
                    required property var modelData
                    readonly property var w: modelData
                    Layout.fillWidth: true
                    color: "transparent"
                    border.color: "#8888aa"
                    border.width: 1
                    radius: 4
                    implicitHeight: cardBody.implicitHeight + 20

                    ColumnLayout {
                        id: cardBody
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            LogosText {
                                objectName: "walletName"
                                Layout.fillWidth: true
                                text: card.w.privateName || card.w.name
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                font.bold: true
                            }
                            LogosText {
                                objectName: "walletState"
                                text: card.w.locked ? "Locked" : "Unlocked"
                                textFormat: Text.PlainText
                                color: card.w.locked ? Theme.palette.textSecondary : Theme.palette.text
                            }
                        }
                        LogosText {
                            visible: !!card.w.privateName
                            Layout.fillWidth: true
                            text: "Shown as “" + card.w.name + "” while locked"
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: Theme.palette.textSecondary
                        }
                        LogosText {
                            Layout.fillWidth: true
                            text: view.holdersText(card.w)
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                        }
                        LogosText {
                            objectName: "walletRule"
                            Layout.fillWidth: true
                            text: view.ruleText(card.w)
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                        }
                        Repeater {
                            model: card.w.locked ? [] : view.accountsOf(card.w.seed)
                            delegate: LogosText {
                                objectName: "walletAccount"
                                Layout.fillWidth: true
                                text: view.accountLine(modelData, card.w.name)
                                textFormat: Text.PlainText
                                elide: Text.ElideMiddle
                                color: Theme.palette.textSecondary
                            }
                        }
                        Repeater {
                            model: view.opensOf(card.w.seed)
                            delegate: RowLayout {
                                objectName: "walletOpen"
                                Layout.fillWidth: true
                                LogosText {
                                    Layout.fillWidth: true
                                    text: modelData.requester + " asks to open this wallet"
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                }
                                LogosButton {
                                    objectName: "walletOpenReview"
                                    text: "Review"
                                    onClicked: view.unlock(card.w.seed, modelData.handle)
                                }
                            }
                        }

                        // ── names ──────────────────────────────────────────
                        ColumnLayout {
                            visible: view.editing === card.w.seed
                            Layout.fillWidth: true
                            spacing: 4
                            LogosTextField {
                                id: publicName
                                objectName: "walletPublicName"
                                Layout.fillWidth: true
                                text: card.w.name
                                placeholderText: "Name shown while locked"
                            }
                            LogosTextField {
                                id: privateName
                                objectName: "walletPrivateName"
                                visible: !card.w.locked
                                Layout.fillWidth: true
                                text: card.w.privateName || ""
                                placeholderText: "Private name, shown only once unlocked (optional)"
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                LogosButton {
                                    text: "Cancel"
                                    onClicked: view.editing = ""
                                }
                                LogosButton {
                                    objectName: "walletNamesSave"
                                    enabled: publicName.text.trim().length > 0
                                    text: "Save"
                                    onClicked: {
                                        // A locked wallet's private name can't be read, so it is left as it is.
                                        if (card.w.locked) view.backend.setNames(card.w.seed, publicName.text, "")
                                        else view.backend.setNames(card.w.seed, publicName.text, privateName.text)
                                        view.editing = ""
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            LogosButton {
                                objectName: "walletUnlock"
                                visible: card.w.locked
                                text: "Unlock…"
                                onClicked: view.unlock(card.w.seed, "")
                            }
                            LogosButton {
                                objectName: "walletLock"
                                visible: !card.w.locked
                                text: "Lock"
                                onClicked: view.backend.lockWallets(JSON.stringify([card.w.seed]))
                            }
                            Item { Layout.fillWidth: true }
                            LogosButton {
                                objectName: "walletNames"
                                text: "Names…"
                                onClicked: view.editing = view.editing === card.w.seed ? "" : card.w.seed
                            }
                            LogosButton {
                                objectName: "walletRuleButton"
                                visible: !card.w.locked
                                text: "Rule…"
                                onClicked: view.rule(card.w.seed)
                            }
                            LogosButton {
                                objectName: "walletKeys"
                                visible: !card.w.locked && (card.w.ways || []).length > 0
                                text: "New keys…"
                                onClicked: view.keys(card.w.seed)
                            }
                        }
                    }
                }
            }

            // ── opens that name no wallet: the person picks one ─────────────
            Repeater {
                model: view.opensOf("")
                delegate: ColumnLayout {
                    id: pick
                    objectName: "pickOpen"
                    Layout.fillWidth: true
                    spacing: 4
                    readonly property bool shown: view.shownOpen.handle === modelData.handle
                    RowLayout {
                        Layout.fillWidth: true
                        LogosText {
                            Layout.fillWidth: true
                            text: modelData.requester + " asks to open a Bitcoin wallet you pick"
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            font.bold: true
                        }
                        LogosButton {
                            visible: !pick.shown
                            text: "Review"
                            onClicked: { view.consentAccount = ""; view.backend.showOpen(modelData.handle) }
                        }
                    }
                    Repeater {
                        model: pick.shown ? view.shownOpen.lines || [] : []
                        delegate: LogosText {
                            Layout.fillWidth: true
                            text: modelData
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            font.family: "monospace"
                        }
                    }
                    Repeater {
                        // Bitcoin accounts of unlocked wallets, of the family asked for.
                        model: !pick.shown ? [] : view.roster.filter(function (a) {
                            var asked = view.shownOpen.asked || {}
                            var unlocked = view.wallets.some(function (w) { return w.seed === a.seed && !w.locked })
                            return unlocked && a.family === asked.family
                        })
                        delegate: LogosRadioButton {
                            objectName: "pickOpenAccount"
                            checkable: false
                            readonly property string group: (modelData.holders || []).length > 0 ? modelData.holders[0].accountId : ""
                            checked: view.consentAccount === group
                            text: view.accountLine(modelData)
                            onClicked: view.consentAccount = group
                        }
                    }
                    RowLayout {
                        visible: pick.shown
                        Layout.fillWidth: true
                        LogosButton {
                            text: "Refuse"
                            onClicked: view.backend.rejectOpen(modelData.handle)
                        }
                        Item { Layout.fillWidth: true }
                        LogosButton {
                            objectName: "pickOpenConsent"
                            enabled: view.consentAccount !== ""
                            text: "Open it for that app"
                            onClicked: view.backend.consentOpen(modelData.handle, view.shownOpen.bundle_id, view.consentAccount)
                        }
                    }
                }
            }

            // ── passwords ───────────────────────────────────────────────────
            LogosText {
                Layout.topMargin: 8
                text: "Passwords"
                textFormat: Text.PlainText
                font.bold: true
            }
            LogosText {
                Layout.fillWidth: true
                text: "A password can unlock several wallets, as each wallet's rule says. Its name shows when you unlock."
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.palette.textSecondary
            }
            Repeater {
                model: view.passwords
                delegate: ColumnLayout {
                    id: pwRow
                    objectName: "passwordRow"
                    Layout.fillWidth: true
                    spacing: 4
                    property string mode: ""
                    RowLayout {
                        Layout.fillWidth: true
                        LogosText {
                            objectName: "passwordName"
                            Layout.fillWidth: true
                            text: "“" + modelData.name + "” · unlocks " + modelData.wallets.length
                                  + " wallet" + (modelData.wallets.length === 1 ? "" : "s")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                        }
                        LogosButton { text: "Rename"; onClicked: pwRow.mode = pwRow.mode === "rename" ? "" : "rename" }
                        LogosButton { text: "Change"; onClicked: pwRow.mode = pwRow.mode === "change" ? "" : "change" }
                        LogosButton {
                            objectName: "passwordRemove"
                            enabled: modelData.wallets.length === 0
                            text: "Remove"
                            onClicked: view.backend.removePassword(modelData.id)
                        }
                    }
                    RowLayout {
                        visible: pwRow.mode === "rename"
                        Layout.fillWidth: true
                        LogosTextField { id: renameField; Layout.fillWidth: true; text: modelData.name }
                        LogosButton {
                            text: "Save"
                            enabled: renameField.text.trim().length > 0
                            onClicked: { view.backend.renamePassword(modelData.id, renameField.text); pwRow.mode = "" }
                        }
                    }
                    ColumnLayout {
                        visible: pwRow.mode === "change"
                        Layout.fillWidth: true
                        LogosTextField {
                            id: oldPw; objectName: "passwordOld"; Layout.fillWidth: true
                            echoMode: TextInput.Password; placeholderText: "Current password"
                            Component.onCompleted: textInput.passwordMaskDelay = 0
                        }
                        LogosTextField {
                            id: newPw; objectName: "passwordNew"; Layout.fillWidth: true
                            echoMode: TextInput.Password; placeholderText: "New password, 8 characters or more"
                            Component.onCompleted: textInput.passwordMaskDelay = 0
                        }
                        LogosTextField {
                            id: newPw2; Layout.fillWidth: true
                            echoMode: TextInput.Password; placeholderText: "New password again"
                            Component.onCompleted: textInput.passwordMaskDelay = 0
                        }
                        LogosButton {
                            objectName: "passwordChangeSave"
                            enabled: oldPw.text.length > 0 && newPw.text.length >= 8 && newPw.text === newPw2.text
                            text: "Change it"
                            onClicked: {
                                view.backend.changePassword(modelData.id, oldPw.text, newPw.text)
                                oldPw.text = ""; newPw.text = ""; newPw2.text = ""
                                pwRow.mode = ""
                            }
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                LogosTextField {
                    id: addName; objectName: "passwordAddName"; Layout.fillWidth: true
                    placeholderText: "New password's name (e.g. Home)"
                }
                LogosTextField {
                    id: addPw; objectName: "passwordAddField"; Layout.fillWidth: true
                    echoMode: TextInput.Password; placeholderText: "Password, 8 characters or more"
                    Component.onCompleted: textInput.passwordMaskDelay = 0
                }
                LogosTextField {
                    id: addPw2; Layout.fillWidth: true
                    echoMode: TextInput.Password; placeholderText: "Password again"
                    Component.onCompleted: textInput.passwordMaskDelay = 0
                }
                LogosButton {
                    objectName: "passwordAdd"
                    enabled: addName.text.trim().length > 0 && addPw.text.length >= 8 && addPw.text === addPw2.text
                    text: "Add password"
                    onClicked: {
                        view.backend.createPassword(addName.text, addPw.text)
                        addName.text = ""; addPw.text = ""; addPw2.text = ""
                    }
                }
            }
        }
    }
}
