import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// Granting an allowance: a new one, a change to one, or the answer to what an app asked for, which
// can be narrowed and not widened. Every limit is optional, and each says what leaving it out means.
Rectangle {
    id: sheet
    objectName: "allowanceSheet"
    property var backend
    // `new`, `change` or `request`.
    property string mode: "new"
    // The allowance being changed.
    property var existing: null
    signal closed()

    color: Theme.palette.background
    border.color: "#8888aa"
    border.width: 1
    radius: 6
    implicitHeight: body.implicitHeight + footer.implicitHeight + 48

    function parse(raw, empty) {
        try { return JSON.parse(raw) } catch (e) { return empty }
    }
    readonly property var shown: parse(backend ? backend.allowanceRequestJson : "{}", ({}))
    readonly property var asked: mode === "request" && shown.asked ? shown.asked.grant : null
    readonly property var roster: parse(backend ? backend.rosterJson : "[]", [])

    function keystoreId(a) {
        var hs = (a.holders || []).filter(function (h) { return h.signer === "keystore_module" })
        return hs.length > 0 ? hs[0].accountId : ""
    }
    readonly property var accounts: roster.filter(function (a) { return sheet.keystoreId(a) !== "" })
    property string account: ""
    readonly property var entry: {
        for (var i = 0; i < accounts.length; i++)
            if (keystoreId(accounts[i]).toLowerCase() === account.toLowerCase()) return accounts[i]
        return null
    }
    readonly property bool bitcoin: entry !== null && String(entry.family).indexOf("bitcoin") === 0
    readonly property var networks: entry && entry.chain === "main" ? ["mainnet"] : ["signet", "testnet4", "testnet", "regtest"]
    readonly property bool editable: mode === "new"

    property string scopeKind: "spend"
    property string network: ""
    property bool review: false
    property bool anyApp: false
    property real keptExpiry: 0
    property string keptHours: ""
    readonly property string pickedNetwork: networks.indexOf(network) >= 0 ? network : networks[0]
    readonly property bool spends: scopeKind === "spend" && (bitcoin || !editable)

    function accountLabel(a) {
        var family = a.family === "evm" ? "Ethereum" : "Bitcoin"
        return family + " · " + (a.label || a.address || keystoreId(a))
    }
    function hoursFrom(ms) {
        return ms > 0 ? String(Math.max(1, Math.ceil((ms - Date.now()) / 3600000))) : ""
    }
    function fill(g) {
        var l = g.limits || {}
        account = g.account
        scopeKind = g.scope.kind
        network = g.scope.network || ""
        review = g.review === true
        anyApp = (g.callers || []).some(function (c) { return c.module === "*" })
        var c = (g.callers || [])[0] || {}
        moduleField.text = c.module === "*" ? "" : (c.module || "")
        forField.text = c["for"] || ""
        perRequest.text = l.perRequest || ""
        total.text = l.total || ""
        periodAmount.text = l.perPeriod ? l.perPeriod.amount : ""
        periodHours.text = l.perPeriod ? String(l.perPeriod.ms / 3600000) : ""
        count.text = l.count !== undefined ? String(l.count) : ""
        maxFee.text = l.maxFee || ""
        destinations.text = (l.destinations || []).join(", ")
        keptExpiry = l.expiresAtMs || 0
        keptHours = hoursFrom(keptExpiry)
        hours.text = keptHours
        endsAtRestart.checked = g.endsAtRestart === true
        password.text = ""
    }
    function reset() {
        if (mode === "change" && existing) {
            fill({ account: existing.account, callers: existing.callers, scope: existing.scope, review: existing.review,
                   endsAtRestart: existing.endsAtRestart, limits: existing.limits })
        } else if (mode === "request" && asked) {
            fill(asked)
        } else {
            var spendable = accounts.length > 0 && String(accounts[0].family).indexOf("bitcoin") === 0
            fill({ account: accounts.length > 0 ? keystoreId(accounts[0]) : "", callers: [], review: !spendable,
                   scope: { kind: spendable ? "spend" : "all" } })
        }
    }
    // The request ended while on screen: nothing is left to answer.
    onAskedChanged: {
        if (mode !== "request") return
        if (asked) fill(asked)
        else if (visible) closed()
    }

    function pickAccount(a) {
        account = keystoreId(a)
        if (String(a.family).indexOf("bitcoin") !== 0) scopeKind = "all"
        if (scopeKind === "all") review = true
    }
    function digits(t) { return /^[0-9]*$/.test(t.trim()) }
    readonly property bool formOk: account !== "" && password.text.length > 0
                                   && (anyApp || moduleField.text.trim() !== "")
                                   && [count, hours].every(function (f) { return sheet.digits(f.text) })
                                   && (!spends || ([perRequest, total, periodAmount, maxFee].every(function (f) { return sheet.digits(f.text) })
                                                   && (periodAmount.text.trim() === "") === (periodHours.text.trim() === "")
                                                   && /^[0-9.]*$/.test(periodHours.text.trim())))
    // Nothing a person would otherwise be asked about limits this one.
    readonly property bool unlimited: !review && [perRequest, total, periodAmount, count, hours].every(function (f) { return f.text.trim() === "" })

    function limits() {
        var l = {}
        var put = function (key, f) { if (f.text.trim() !== "") l[key] = f.text.trim() }
        if (spends) {
            put("perRequest", perRequest)
            put("total", total)
            put("maxFee", maxFee)
            if (periodAmount.text.trim() !== "")
                l.perPeriod = { amount: periodAmount.text.trim(), ms: Math.round(Number(periodHours.text) * 3600000) }
            var places = destinations.text.split(",").map(function (d) { return d.trim() }).filter(function (d) { return d !== "" })
            if (places.length > 0) l.destinations = places
        }
        if (count.text.trim() !== "") l.count = Number(count.text)
        if (hours.text.trim() !== "")
            l.expiresAtMs = keptExpiry > 0 && hours.text.trim() === keptHours ? keptExpiry : Date.now() + Number(hours.text) * 3600000
        return l
    }
    function grant() {
        var done = function (ok) { if (ok) sheet.closed() }
        if (mode === "request") {
            var decided = { limits: limits(), review: review, endsAtRestart: endsAtRestart.checked }
            logos.watch(backend.approveAllowanceRequest(shown.handle, shown.bundle_id, JSON.stringify(decided), password.text), done)
        } else {
            var caller = { module: anyApp ? "*" : moduleField.text.trim() }
            if (!anyApp && forField.text.trim() !== "") caller["for"] = forField.text.trim()
            var g = { account: account, callers: mode === "change" ? existing.callers : [caller], limits: limits(), review: review,
                      scope: scopeKind === "spend" ? { kind: "spend", network: mode === "change" ? existing.scope.network : pickedNetwork } : { kind: "all" },
                      endsAtRestart: endsAtRestart.checked }
            if (mode === "change") g.replaces = { id: existing.id, version: existing.version }
            logos.watch(backend.grantAllowance(JSON.stringify(g), password.text), done)
        }
        password.text = ""
    }

    component Heading: LogosText {
        Layout.fillWidth: true
        Layout.topMargin: 6
        textFormat: Text.PlainText
        font.bold: true
    }
    component Hint: LogosText {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.palette.textSecondary
    }
    component Limit: ColumnLayout {
        property alias label: limitLabel.text
        property alias text: limitField.text
        property alias placeholder: limitField.placeholderText
        property string name: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 2
        LogosText {
            id: limitLabel
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
        LogosTextField {
            id: limitField
            objectName: name
            Layout.fillWidth: true
        }
    }

    ScrollView {
        id: scroller
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top; margins: 16 }
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            id: body
            width: scroller.availableWidth
            spacing: 6

            LogosText {
                objectName: "allowanceSheetTitle"
                Layout.fillWidth: true
                text: sheet.mode === "request" ? (sheet.shown.requester || "An app") + " asks for an allowance"
                    : sheet.mode === "change" ? "Change this allowance" : "New allowance"
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.bold: true
            }
            // The manager's words for what was asked, and the app's own reason marked as its claim.
            Repeater {
                model: sheet.mode === "request" ? (sheet.shown.lines || []) : []
                delegate: LogosText {
                    objectName: "allowanceAskedLine"
                    required property string modelData
                    Layout.fillWidth: true
                    text: modelData
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }
            }
            Hint {
                visible: sheet.mode === "request"
                text: "You can tighten what it asks for below, but not loosen it."
            }

            // ── which account ───────────────────────────────────────────────
            Heading { visible: sheet.editable; text: "Account" }
            Hint {
                visible: sheet.editable && sheet.accounts.length === 0
                text: "Only accounts in this device's keystore can have an allowance. A Keycard or QR wallet asks on the device each time."
            }
            Repeater {
                model: sheet.editable ? sheet.accounts : []
                delegate: LogosRadioButton {
                    objectName: "allowanceAccountChoice"
                    required property var modelData
                    Layout.fillWidth: true
                    checkable: false
                    checked: sheet.keystoreId(modelData).toLowerCase() === sheet.account.toLowerCase()
                    text: sheet.accountLabel(modelData)
                    onClicked: sheet.pickAccount(modelData)
                }
            }

            // ── which app ───────────────────────────────────────────────────
            Heading { visible: sheet.editable; text: "App" }
            LogosTextField {
                id: moduleField
                objectName: "allowanceModule"
                visible: sheet.editable && !sheet.anyApp
                Layout.fillWidth: true
                placeholderText: "Module name, such as bitcoin_wallet_core_module"
            }
            LogosTextField {
                id: forField
                objectName: "allowanceFor"
                visible: sheet.editable && !sheet.anyApp
                Layout.fillWidth: true
                placeholderText: "For an app behind it (optional)"
            }
            LogosCheckbox {
                id: anyAppBox
                objectName: "allowanceAnyApp"
                visible: sheet.editable && sheet.review
                checkable: false
                checked: sheet.anyApp
                text: "Any app, since you see each signature"
                onClicked: sheet.anyApp = !sheet.anyApp
            }

            // ── what it covers ──────────────────────────────────────────────
            Heading { visible: sheet.editable; text: "What it covers" }
            LogosRadioButton {
                objectName: "allowanceScopeSpend"
                visible: sheet.editable && sheet.bitcoin
                Layout.fillWidth: true
                checkable: false
                checked: sheet.scopeKind === "spend"
                text: "Spending Bitcoin from this wallet"
                onClicked: sheet.scopeKind = "spend"
            }
            RowLayout {
                visible: sheet.editable && sheet.spends && sheet.networks.length > 1
                Layout.leftMargin: 24
                spacing: 8
                Repeater {
                    model: sheet.networks
                    delegate: LogosRadioButton {
                        objectName: "allowanceNetwork_" + modelData
                        required property string modelData
                        checkable: false
                        checked: sheet.pickedNetwork === modelData
                        text: modelData
                        onClicked: sheet.network = modelData
                    }
                }
            }
            LogosRadioButton {
                objectName: "allowanceScopeAll"
                visible: sheet.editable
                Layout.fillWidth: true
                checkable: false
                checked: sheet.scopeKind === "all"
                text: "Every kind of request, each shown to you"
                onClicked: { sheet.scopeKind = "all"; sheet.review = true }
            }

            // ── how it signs ────────────────────────────────────────────────
            Heading { text: "How it signs" }
            LogosRadioButton {
                objectName: "allowanceReviewOff"
                visible: sheet.scopeKind === "spend" && !(sheet.asked && sheet.asked.review)
                Layout.fillWidth: true
                checkable: false
                checked: !sheet.review
                text: "Without showing me each signature"
                onClicked: { sheet.review = false; sheet.anyApp = false }
            }
            LogosRadioButton {
                objectName: "allowanceReviewOn"
                Layout.fillWidth: true
                checkable: false
                checked: sheet.review
                text: "Show me each signature to confirm, with no password"
                onClicked: sheet.review = true
            }

            // ── limits ──────────────────────────────────────────────────────
            Heading { text: "Limits" }
            Hint { text: "All optional: a limit left empty doesn't limit. Anything over a limit comes to you for your password." }
            RowLayout {
                visible: sheet.spends
                Layout.fillWidth: true
                spacing: 12
                Limit { id: perRequest; name: "allowancePerRequest"; label: "Each signature, in sats"; placeholder: "No limit" }
                Limit { id: total; name: "allowanceTotal"; label: "In total, in sats"; placeholder: "No limit" }
            }
            RowLayout {
                visible: sheet.spends
                Layout.fillWidth: true
                spacing: 12
                Limit { id: periodAmount; name: "allowancePeriodAmount"; label: "Per period, in sats"; placeholder: "No limit" }
                Limit { id: periodHours; name: "allowancePeriodHours"; label: "Period, in hours"; placeholder: "Hours" }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Limit { id: count; name: "allowanceCount"; label: "Number of signatures"; placeholder: "No limit" }
                Limit { id: hours; name: "allowanceHours"; label: "Ends after, in hours"; placeholder: "Doesn't end" }
            }
            Limit {
                id: maxFee
                name: "allowanceMaxFee"
                visible: sheet.spends
                label: "Fee of each signature, in sats"
                placeholder: "No limit"
            }
            Limit {
                id: destinations
                name: "allowanceDestinations"
                visible: sheet.spends
                label: "Pays only these addresses, separated by commas"
                placeholder: "Any address"
            }

            LogosCheckbox {
                id: endsAtRestart
                objectName: "allowanceEndsAtRestart"
                Layout.topMargin: 4
                text: "End this allowance when the app restarts"
            }
            Hint {
                visible: !endsAtRestart.checked
                text: "After a restart it waits, with what it has spent, until you enter the password again."
            }

            LogosText {
                objectName: "allowanceWarning"
                visible: sheet.unlimited && sheet.spends
                Layout.fillWidth: true
                text: "Nothing limits this: the app could spend everything in this wallet without asking you."
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.palette.error
            }
            LogosText {
                objectName: "allowanceAnyWarning"
                visible: sheet.anyApp
                Layout.fillWidth: true
                text: "Any app could ask. Read each signature before you confirm it."
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.palette.error
            }
            LogosText {
                objectName: "allowanceSheetError"
                visible: !!(sheet.backend && sheet.backend.allowanceError)
                Layout.fillWidth: true
                text: (sheet.backend && sheet.backend.allowanceError) || ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.palette.error
            }
        }
    }

    ColumnLayout {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
        spacing: 8

        LogosTextField {
            id: password
            objectName: "allowancePassword"
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: "Wallet password"
            Component.onCompleted: textInput.passwordMaskDelay = 0
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            LogosButton {
                objectName: "allowanceCancel"
                text: sheet.mode === "request" ? "Back" : "Cancel"
                onClicked: { password.text = ""; sheet.closed() }
            }
            LogosButton {
                objectName: "allowanceRefuse"
                visible: sheet.mode === "request"
                text: "Refuse"
                onClicked: { password.text = ""; sheet.backend.rejectAllowanceRequest(sheet.shown.handle); sheet.closed() }
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                objectName: "allowanceGrant"
                enabled: sheet.formOk
                text: sheet.mode === "change" ? "Save" : "Allow"
                onClicked: sheet.grant()
            }
        }
    }
}
