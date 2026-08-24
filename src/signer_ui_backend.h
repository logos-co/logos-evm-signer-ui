#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>

#include "rep_signer_ui_source.h"
#include "logos_ui_plugin_context.h"

// The signer UI backend.
//
// Every keystore call is made here, over the generated typed client: one client,
// one session token, negotiated once and reused. The QML half renders and takes
// the password; it makes no module calls of its own.
//
// The backend is deliberately incurious about WHAT is being signed. It never
// parses an intent — it cannot, it has no client for any wallet or chain module
// — and it passes the keystore's render lines through untouched.
class SignerUiBackend : public SignerUiSimpleSource,
                        public LogosUiPluginContext
{
public:
    void refresh() override;
    void acknowledge(QString handle) override;
    bool approve(QString handle, QString bundleId, QString password) override;
    bool reject(QString handle) override;
    void dismiss() override;

protected:
    void onContextReady() override;

private:
    void clearRendered();
    void startDwell();

    // Guards against a render painted into a hidden or just-appeared sheet
    // being approved by a click that was already travelling.
    QTimer m_dwell;
    // Polls the queue. Events are the fast path; this is the backstop that
    // makes a missed subscription edge cost latency rather than correctness.
    QTimer m_poll;
};
