#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QJsonObject>
#include <QDateTime>
#include <QTimer>

#include "rep_evm_signer_ui_source.h"
#include "logos_ui_plugin_context.h"

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
    bool approve(QString handle, QString bundleId, QString password) override;
    bool reject(QString handle) override;
    void dismiss() override;
    bool qrPress() override;
    bool qrCancel() override;

protected:
    void onContextReady() override;

private:
    void clearRendered();
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

    /// The scanner's handle for this app's claim on drawing sessions; empty while none is held,
    /// or where qr_scanner_module isn't installed.
    QString m_qrHandle;
    /// Names the codes in `qrFramesJson`, which the scanner then doesn't send again.
    QString m_qrFramesId;
    QTimer m_qrPoll;
    bool m_qrInFlight = false;

    /// Built once: it parses ~430KB of ABI JSON. Null if that ever fails, in
    /// which case interpretation is simply absent.
    LogosTxDecoder *m_decoder = nullptr;

    /// Guards against the poll timer stacking a refresh behind one that is
    /// still blocked in a synchronous call.
    bool m_inFlight = false;

    /// Until when an "Approved" confirmation outranks the queue status.
    QDateTime m_confirmUntil;

    // Guards against a render painted into a hidden or just-appeared sheet
    // being approved by a click that was already travelling.
    QTimer m_dwell;
    // Polls the queue. Events are the fast path; this is the backstop that
    // makes a missed subscription edge cost latency rather than correctness.
    QTimer m_poll;
};
