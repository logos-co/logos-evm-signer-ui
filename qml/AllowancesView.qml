import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// What apps may have signed without the password. An allowance only ever removes a prompt: what
// falls outside one still comes to Requests. The lines on each card are the manager's own.
ColumnLayout {
    id: view
    objectName: "allowancesView"
    property var backend
    signal grantNew()
    signal change(var allowance)
    signal review(string handle)
    spacing: 10

    function parse(raw, empty) {
        try { return JSON.parse(raw) } catch (e) { return empty }
    }
    readonly property var state_: parse(backend ? backend.allowancesJson : "{}", ({}))
    readonly property var allowances: state_.allowances || []
    readonly property var requests: parse(backend ? backend.allowanceRequestsJson : "[]", [])
    readonly property var roster: parse(backend ? backend.rosterJson : "[]", [])
    readonly property var history: parse(backend ? backend.unattendedJson : "[]", [])

    function accountName(id) {
        var want = String(id).toLowerCase()
        for (var i = 0; i < roster.length; i++) {
            var holders = roster[i].holders || []
            for (var j = 0; j < holders.length; j++)
                if (String(holders[j].accountId).toLowerCase() === want)
                    return roster[i].label || roster[i].address || id
        }
        return id
    }
    function callersText(a) {
        return (a.callers || []).map(function (c) {
            if (c.module === "*") return "Any app"
            return c["for"] ? c["for"] + " through " + c.module : c.module
        }).join(", ")
    }
    function stateText(a) {
        return a.state === "active" ? "Active" : a.state === "waiting" ? "Waiting for the password" : "Ended"
    }
    function usedText(a) {
        var n = (a.used || {}).count || 0
        var count = n + (n === 1 ? " signature" : " signatures")
        return a.scope.kind === "spend" ? "Used: " + a.used.spent + " sats · " + count : "Used: " + count
    }
    function howText(h) {
        return h.how === "unattended" ? "Signed without asking" : h.how === "reviewed" ? "Confirmed by you"
             : h.how === "password" ? "Past its allowance, with your password" : "Signed"
    }

    RowLayout {
        Layout.fillWidth: true
        LogosText {
            text: "Allowances"
            textFormat: Text.PlainText
            font.bold: true
        }
        Item { Layout.fillWidth: true }
        LogosButton {
            objectName: "newAllowanceButton"
            enabled: !!view.backend && view.state_.locked !== true
            text: "New allowance…"
            onClicked: view.grantNew()
        }
    }
    LogosText {
        Layout.fillWidth: true
        text: "An allowance lets an app have an account sign without its password. Anything outside it still comes to you."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.palette.textSecondary
    }
    LogosText {
        objectName: "allowanceError"
        visible: !!(view.backend && view.backend.allowanceError)
        Layout.fillWidth: true
        text: (view.backend && view.backend.allowanceError) || ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.palette.error
    }
    LogosText {
        objectName: "allowancesLocked"
        visible: view.state_.locked === true
        Layout.fillWidth: true
        text: "Unlock a wallet in Wallets to see and use allowances. While every wallet is locked, nothing is signed under one."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    LogosText {
        objectName: "allowancesUnreadable"
        visible: view.state_.unreadable === true
        Layout.fillWidth: true
        text: "The saved allowances could not be read, so none apply and new ones can't be saved."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.palette.error
    }

    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 10

            // ── what apps are asking for ────────────────────────────────────
            Repeater {
                model: view.requests
                delegate: Rectangle {
                    objectName: "allowanceRequest"
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: askRow.implicitHeight + 20
                    color: "transparent"
                    border.color: "#8888aa"
                    border.width: 1
                    radius: 4
                    RowLayout {
                        id: askRow
                        anchors.fill: parent
                        anchors.margins: 10
                        LogosText {
                            Layout.fillWidth: true
                            text: modelData.requester + " asks for an allowance"
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                        }
                        LogosButton {
                            objectName: "allowanceRequestReview"
                            text: "Review…"
                            onClicked: view.review(modelData.handle)
                        }
                    }
                }
            }

            LogosText {
                objectName: "noAllowances"
                visible: view.allowances.length === 0 && view.requests.length === 0 && view.state_.locked !== true
                Layout.fillWidth: true
                text: "No app has an allowance. Every signature asks for your password."
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }

            // ── what stands ─────────────────────────────────────────────────
            Repeater {
                model: view.allowances
                delegate: Rectangle {
                    id: card
                    objectName: "allowanceCard"
                    required property var modelData
                    readonly property var a: modelData
                    property bool resuming: false
                    Layout.fillWidth: true
                    implicitHeight: cardBody.implicitHeight + 20
                    color: "transparent"
                    border.color: "#8888aa"
                    border.width: 1
                    radius: 4
                    opacity: a.state === "ended" ? 0.7 : 1

                    ColumnLayout {
                        id: cardBody
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            LogosText {
                                objectName: "allowanceCallers"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                text: view.callersText(card.a)
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                font.bold: true
                            }
                            LogosBadge {
                                objectName: "allowanceState"
                                text: view.stateText(card.a)
                                color: card.a.state === "active" ? Theme.palette.text : Theme.palette.textSecondary
                            }
                        }
                        LogosText {
                            objectName: "allowanceAccount"
                            Layout.fillWidth: true
                            text: view.accountName(card.a.account)
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: Theme.palette.textSecondary
                        }
                        Repeater {
                            // The first line names the callers, already the card's title.
                            model: (card.a.lines || []).slice(1)
                            delegate: LogosText {
                                objectName: "allowanceLine"
                                required property string modelData
                                Layout.fillWidth: true
                                text: modelData
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                            }
                        }
                        LogosText {
                            objectName: "allowanceUsed"
                            Layout.fillWidth: true
                            text: view.usedText(card.a)
                            textFormat: Text.PlainText
                            color: Theme.palette.textSecondary
                        }

                        RowLayout {
                            visible: card.resuming
                            Layout.fillWidth: true
                            spacing: 8
                            LogosTextField {
                                id: resumePassword
                                objectName: "allowanceResumePassword"
                                Layout.fillWidth: true
                                echoMode: TextInput.Password
                                placeholderText: "Wallet password"
                                Component.onCompleted: textInput.passwordMaskDelay = 0
                            }
                            LogosButton {
                                objectName: "allowanceResumeConfirm"
                                enabled: resumePassword.text.length > 0
                                text: "Start"
                                onClicked: {
                                    logos.watch(view.backend.resumeAllowances(card.a.account, resumePassword.text),
                                                function (ok) { if (ok) card.resuming = false })
                                    resumePassword.text = ""
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            LogosButton {
                                objectName: "allowanceResume"
                                visible: card.a.state === "waiting" && !card.resuming
                                text: "Start again…"
                                onClicked: card.resuming = true
                            }
                            Item { Layout.fillWidth: true }
                            LogosButton {
                                objectName: "allowanceChange"
                                visible: card.a.state !== "ended"
                                text: "Change…"
                                onClicked: view.change(card.a)
                            }
                            LogosButton {
                                objectName: "allowanceRemove"
                                text: "Remove"
                                onClicked: view.backend.revokeAllowance(card.a.id)
                            }
                        }
                    }
                }
            }

            // ── what was signed ─────────────────────────────────────────────
            LogosText {
                objectName: "allowanceHistoryHeading"
                visible: view.history.length > 0
                Layout.topMargin: 8
                text: "Recent signatures"
                textFormat: Text.PlainText
                font.bold: true
            }
            Repeater {
                model: view.history.slice(-20).reverse()
                delegate: LogosText {
                    objectName: "allowanceHistoryLine"
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.requester + " · " + view.howText(modelData)
                          + (modelData.spendSat ? " · " + modelData.spendSat + " sats" : "")
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
