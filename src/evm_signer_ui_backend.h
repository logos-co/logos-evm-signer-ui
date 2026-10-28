#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QJsonObject>
#include <QDateTime>
#include <QTimer>

#include "rep_evm_signer_ui_source.h"
#include "logos_ui_plugin_context.h"
#include "sheet_lines.h"

struct LogosTxDecoder;

// The signer UI backend.
//
// Every signer manager call is made here, over the generated typed client: one client,
// one session token, negotiated once and reused. The QML half renders and takes
// the password; it makes no module calls of its own.
//
// The manager's render lines pass through untouched; the backend may not
// reformat or re-order them. It additionally decodes the calldata found IN those
// lines, offline, via the linked-in logos-tx-decoder, and publishes the reading
// separately as `interpretationLines`. It has no client for any wallet or chain
// module, so the decode can only ever describe bytes already on screen.
//
// Under that decode it may add what `token_list_module` — an OPTIONAL dependency
// — calls the address being signed to, and the amount in that token's units. A
// NAME, never a check of the code: it cannot move the decoder's tiers, it says
// which list answered, and absent is a normal state.
class EvmSignerUiBackend : public EvmSignerUiSimpleSource,
                           public LogosUiPluginContext
{
public:
    ~EvmSignerUiBackend() override;

    void refresh() override;
    void refreshUnattended() override;
    bool acknowledge(QString handle) override;
    bool chooseSigner(QString handle, QString signer) override;
    bool approve(QString handle, QString bundleId, QString password) override;
    bool reject(QString handle) override;
    void dismiss() override;
    bool qrPress() override;
    bool qrCancel() override;

    void refreshWallets() override;
    bool unlockWallet(QString seed, QString way, QString holder, QString secret, QString passwordsJson) override;
    bool retryUnlock(QString passwordsJson) override;
    bool cancelUnlock() override;
    bool lockWallets(QString seedsJson) override;
    bool setRule(QString seed, QString waysJson, QString holder, QString secret, QString passwordsJson) override;
    bool changeKeys(QString seed, bool newIndex, QString holder, QString secret, QString passwordsJson) override;
    bool setNames(QString seed, QString name, QString privateName) override;
    QString createPassword(QString name, QString password) override;
    bool renamePassword(QString id, QString name) override;
    bool changePassword(QString id, QString oldPassword, QString newPassword) override;
    bool removePassword(QString id) override;
    bool showOpen(QString handle) override;
    bool consentOpen(QString handle, QString bundleId, QString group) override;
    bool rejectOpen(QString handle) override;

protected:
    void onContextReady() override;

private:
    void clearRendered();
    /// Who signs the request on screen, and who else could, from the manager's reply.
    void applySigner(const QJsonObject &r);
    /// Read the signers again: one was plugged in or out, or the default moved.
    void refreshSigners();
    /// The manager's signers for the request on screen, applied; `presence` is the chosen one's.
    bool readSigners(QString *presence);
    /// Decode the calldata in `lines`. Empty on any failure — the verbatim
    /// lines are complete on their own, so a decoder problem must not surface
    /// as an approval problem.
    QStringList interpret(const QStringList &lines) const;
    /// What a token list calls this leg's address, or nothing. Empty whenever the
    /// module is absent, which is the ordinary case on a signing device.
    QStringList tokenListLines(const QJsonObject &leg) const;
    /// Name the request on screen as the user's installed package does, once package_manager answers.
    void nameRequester(const QString &handle, const QString &module);
    void startDwell();
    /// Refresh on a clean event-loop stack. Use this from event callbacks:
    /// calling out synchronously from an IPC callback deadlocks the reply.
    void refreshSoon();
    /// A QR wallet's request on screen: draw its session here, so the scanner opens no window.
    void qrClaim();
    /// The request is gone: let the scanner go, off the IPC stack.
    void qrRelease();
    void qrPoll();
    /// Is a QR wallet's unlock step drawn here now?
    bool qrUnlocking() const;

    /// A step that may need the device: `unlock_wallet`, `set_rule` or `change_keys` with `body`.
    /// Its secret parts are wiped once sent.
    bool beginStep(const QString &method, const QString &seed, const QString &holder, QJsonObject body,
                   QString secret, QString passwordsJson);
    /// Follow the device step under way, and end it once it settles.
    void unlockPoll();
    void endStep(const QString &seed, bool ok);
    /// A wallet call's reply: true when the manager said ok, else its error under the Wallets view.
    bool walletReply(const QString &reply, const QString &fallback);

    /// The scanner's handle for this app's claim on drawing sessions; empty while none is held,
    /// or where qr_scanner_module isn't installed.
    QString m_qrHandle;
    /// Names the codes in `qrFramesJson`, which the scanner then doesn't send again.
    QString m_qrFramesId;
    QTimer m_qrPoll;
    bool m_qrInFlight = false;
    /// Follows a wallet's device step.
    QTimer m_unlockPoll;
    /// The Wallets view's backstop.
    QTimer m_walletsPoll;
    bool m_walletsInFlight = false;

    /// Built once: it parses ~430KB of ABI JSON. Null if that ever fails, in
    /// which case interpretation is simply absent.
    LogosTxDecoder *m_decoder = nullptr;

    /// Guards against the poll timer stacking a refresh behind one that is
    /// still blocked in a synchronous call.
    bool m_inFlight = false;

    /// Until when an "Approved" confirmation outranks the queue status.
    QDateTime m_confirmUntil;

    /// Which error under the sheet the poll or a signer change may clear.
    sheet::ErrorHold m_errors;

    // Guards against a render painted into a hidden or just-appeared sheet
    // being approved by a click that was already travelling.
    QTimer m_dwell;
    // Polls the queue. Events are the fast path; this is the backstop that
    // makes a missed subscription edge cost latency rather than correctness.
    QTimer m_poll;
};
