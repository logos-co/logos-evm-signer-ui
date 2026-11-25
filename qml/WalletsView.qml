import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "accountkit" as Accounts

// Every wallet, whichever signers hold it: its names, its holders, how it unlocks, its accounts
// once unlocked, and the apps waiting to open it. Read-only: a wallet is renamed or removed in the
// app that owns it (Keys, Keycard, QR Wallets), and device setup stays there too. Here it is only
// unlocked, locked, and given its unlock rule.
ColumnLayout {
    id: view
    objectName: "walletsView"
    property var backend
    signal unlock(string seed, string openHandle)
    signal rule(string seed)
    signal keys(string seed)
    spacing: 10

    // A lock glyph on a locked wallet. No edit or trash icon: the Signer doesn't rename or remove.
    readonly property url iconLock: Qt.resolvedUrl("assets/lock.svg")

    function parse(raw, empty) {
        try { return JSON.parse(raw) } catch (e) { return empty }
    }
    readonly property var settings: parse(backend ? backend.walletsJson : "{}", ({}))
    readonly property var wallets: settings.wallets || []
    readonly property var passwords: settings.passwords || []
    readonly property var roster: parse(backend ? backend.rosterJson : "[]", [])
    readonly property var opens: parse(backend ? backend.opensJson : "[]", [])
    readonly property var shownOpen: parse(backend ? backend.openJson : "{}", ({}))

    function accountsOf(seed) { return roster.filter(function (a) { return a.seed === seed }) }
    // The master fingerprint its accounts carry: the Wallet ID every holder's app shows.
    function fingerprintOf(entries) {
        for (var i = 0; i < entries.length; i++)
            if (entries[i].wallet && entries[i].wallet.fingerprint) return entries[i].wallet.fingerprint
        return ""
    }
    function opensOf(seed) { return opens.filter(function (o) { return (o.seed || "") === seed }) }
    function holderLabel(h) {
        var named = { keystore: "Keystore", keycard: "Keycard", keycard_shell: "Keycard Shell", qr: "QR wallet" }
        return named[h.kind] || h.signer
    }
    // The apps a wallet is renamed or removed in: the ones its holders belong to.
    function ownerApp(h) {
        var apps = { keystore: "the Keys app", keycard: "the Keycard app", keycard_shell: "the Keycard app", qr: "QR Wallets" }
        return apps[h.kind] || ""
    }
    function ownerText(w) {
        var out = []
        for (var i = 0; i < (w.holders || []).length; i++) {
            var a = ownerApp(w.holders[i])
            if (a && out.indexOf(a) < 0) out.push(a)
        }
        return out.length > 0 ? "Rename or remove it in " + out.join(" or ") + "." : ""
    }
    function holdersText(w) {
        var seen = [], out = []
        for (var i = 0; i < (w.holders || []).length; i++) {
            var l = holderLabel(w.holders[i])
            if (seen.indexOf(l) < 0) { seen.push(l); out.push(l) }
        }
        return "Held by " + out.join(", ")
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
        if (w.alwaysUnlocked) return "Always unlocked: its data here isn't protected."
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

    property string consentAccount: ""

    // Content is capped and centred at 560, matching the Keycard app's wallet column.
    readonly property int contentWidth: 560
    // No "Wallets" heading or "Lock all" here: the app title names it and carries the Lock all action.
    LogosText {
        objectName: "walletError"
        visible: !!(view.backend && view.backend.walletError)
        Layout.fillWidth: true
        Layout.maximumWidth: view.contentWidth
        Layout.alignment: Qt.AlignHCenter
        text: (view.backend && view.backend.walletError) || ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.palette.error
    }
    EmptyState {
        visible: view.wallets.length === 0
        title: "No wallets yet"
        subtitle: "Add a wallet in the Keys app, the Keycard app or QR Wallets, and it shows up here to unlock and use."
    }

    ScrollView {
        id: walletScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: Math.min(walletScroll.availableWidth, view.contentWidth)
            x: Math.max(0, (walletScroll.availableWidth - width) / 2)
            spacing: 10

            Repeater {
                model: view.wallets
                delegate: Accounts.WalletCard {
                    id: card
                    required property var modelData
                    readonly property var w: modelData
                    readonly property var mine: view.accountsOf(w.seed)
                    readonly property var waiting: view.opensOf(w.seed)
                    Layout.fillWidth: true
                    namePrefix: "wallet"
                    title: w.privateName || w.name
                    // Wallet ID = the master fingerprint its accounts carry (shown once unlocked);
                    // the seed is the keyUid it is recognized by, kept to the tooltip.
                    walletId: view.fingerprintOf(mine)
                    walletIdFull: w.seed
                    lockIcon: view.iconLock
                    // The lock glyph already marks a locked wallet, and an unlocked one shows its
                    // accounts and a Lock button; only "Always unlocked" (unprotected) needs saying.
                    stateText: w.alwaysUnlocked ? "Always unlocked" : ""
                    lines: [view.holdersText(w) + " · " + view.ruleText(w)]
                           .concat(w.privateName ? ["Shown as “" + w.name + "” while locked"] : [])
                           .concat(view.ownerText(w) ? [view.ownerText(w)] : [])
                    locked: w.locked
                    lockedText: "Locked · its ID and accounts show once you unlock it."
                    accounts: w.locked ? [] : mine
                    // An app waiting to open this wallet.
                    strips: waiting.map(function (o) {
                        return { text: o.requester + " asks to open this wallet", actions: [{ id: "review", label: "Review" }] }
                    })
                    // Unlock is the one thing to do on a locked wallet: primary, in the locked row.
                    lockedActions: w.locked ? [{ id: "unlock", label: "Unlock" }] : []
                    // Bottom row: Lock on the left; Rule and New keys on the right (unlocked only).
                    leftActions: !w.locked && !w.alwaysUnlocked ? [{ id: "lock", label: "Lock" }] : []
                    rightActions: (w.locked ? [] : [{ id: "rule", label: "Rule…" }])
                                  .concat(!w.locked && (w.ways || []).length > 0 ? [{ id: "keys", label: "New keys…" }] : [])
                    onAction: function (id) {
                        if (id === "unlock") view.unlock(card.w.seed, "")
                        else if (id === "lock") view.backend.lockWallets(JSON.stringify([card.w.seed]))
                        else if (id === "rule") view.rule(card.w.seed)
                        else if (id === "keys") view.keys(card.w.seed)
                    }
                    onStripAction: function (i, id) { view.unlock(card.w.seed, card.waiting[i].handle) }
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

        }
    }
}
