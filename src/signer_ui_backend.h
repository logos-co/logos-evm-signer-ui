#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QDateTime>
#include <QTimer>

#include "rep_signer_ui_source.h"
#include "logos_ui_plugin_context.h"

struct LogosTxDecoder;

// The signer UI backend.
//
// Every keystore call is made here, over the generated typed client: one client,
// one session token, negotiated once and reused. The QML half renders and takes
// the password; it makes no module calls of its own.
//
// The keystore's render lines pass through untouched; the backend may not
// reformat or re-order them. It additionally decodes the calldata found IN those
// lines, offline, via the linked-in logos-tx-decoder, and publishes the reading
// separately as `interpretationLines`. It still has no client for any wallet or
// chain module, so the decode can only ever describe bytes already on screen.
class SignerUiBackend : public SignerUiSimpleSource,
                        public LogosUiPluginContext
{
public:
    ~SignerUiBackend() override;

    void refresh() override;
    void acknowledge(QString handle) override;
    bool approve(QString handle, QString bundleId, QString password) override;
    bool reject(QString handle) override;
    void dismiss() override;

protected:
    void onContextReady() override;

private:
    void clearRendered();
    /// Decode the calldata in `lines`. Empty on any failure — the verbatim
    /// lines are complete on their own, so a decoder problem must not surface
    /// as an approval problem.
    QStringList interpret(const QStringList &lines) const;
    void startDwell();
    /// Refresh on a clean event-loop stack. Use this from event callbacks:
    /// calling out synchronously from an IPC callback deadlocks the reply.
    void refreshSoon();

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
