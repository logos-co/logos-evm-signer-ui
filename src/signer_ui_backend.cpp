#include "signer_ui_backend.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include "logos_sdk.h"

namespace {

/// How long the sheet must have been up before Approve arms. Cheap protection
/// against a click that was already in flight when the sheet appeared; it is
/// NOT protection against an attacker who can drive the QML directly, and the
/// docs say so rather than implying otherwise.
constexpr int kDwellMs = 500;

/// The queue backstop. Events are the fast path.
constexpr int kPollMs = 1000;

QJsonObject parseObject(const QString &raw)
{
    return QJsonDocument::fromJson(raw.toUtf8()).object();
}

} // namespace

void SignerUiBackend::onContextReady()
{
    m_dwell.setSingleShot(true);
    QObject::connect(&m_dwell, &QTimer::timeout, [this] { setDwellElapsed(true); });

    // Subscribe FIRST, then reconcile. The other order loses any request
    // created between the snapshot and the subscription becoming live; this
    // order can only ever produce a duplicate, which the queue de-dupes by
    // handle.
    modules().keystore_module.onApproval_offered([this](QString) { refresh(); });
    modules().keystore_module.onApproval_settled([this](QString handle, QString) {
        if (handle == renderedHandle()) {
            clearRendered();
        }
        refresh();
    });

    QObject::connect(&m_poll, &QTimer::timeout, [this] { refresh(); });
    m_poll.start(kPollMs);

    refresh();
    setStatusText(QStringLiteral("Ready"));
}

void SignerUiBackend::refresh()
{
    const QJsonObject reply = parseObject(modules().keystore_module.pending());
    if (!reply.value(QStringLiteral("ok")).toBool()) {
        // The commonest cause is not being the configured approver, which is a
        // deployment fact rather than a transient error — say so plainly.
        setLastError(QStringLiteral("This build is not registered as the approver."));
        setStatusText(QStringLiteral("Not the approver"));
        return;
    }
    setLastError(QString());
    const QJsonArray items = reply.value(QStringLiteral("pending")).toArray();
    setPendingJson(QString::fromUtf8(QJsonDocument(items).toJson(QJsonDocument::Compact)));
    setStatusText(items.isEmpty() ? QStringLiteral("Nothing to approve")
                                  : QStringLiteral("%1 waiting").arg(items.size()));
}

void SignerUiBackend::acknowledge(QString handle)
{
    const QJsonObject r = parseObject(modules().keystore_module.acknowledge(handle));
    if (!r.value(QStringLiteral("ok")).toBool()) {
        setLastError(r.value(QStringLiteral("error")).toString(QStringLiteral("could not open that request")));
        clearRendered();
        return;
    }

    // Verbatim. The keystore is the only party that parsed the intent, so it is
    // the only one that can tell requester-supplied text from its own — this
    // backend must not "improve" any of it.
    QStringList lines;
    for (const QJsonValue &v : r.value(QStringLiteral("render_lines")).toArray()) {
        lines << v.toString();
    }

    setLastError(QString());
    setRenderedRequester(r.value(QStringLiteral("requester")).toString());
    setRenderedBundleId(r.value(QStringLiteral("bundle_id")).toString());
    setRenderLines(lines);
    setRenderedHandle(r.value(QStringLiteral("handle")).toString());
    startDwell();
}

bool SignerUiBackend::approve(QString handle, QString bundleId, QString password)
{
    // Refuse anything that is not what is currently on screen, and refuse it
    // before the password is used for anything.
    if (handle.isEmpty() || handle != renderedHandle() || bundleId != renderedBundleId()) {
        setLastError(QStringLiteral("That is not the request on screen."));
        password.fill(QChar(0));
        return false;
    }
    if (!dwellElapsed()) {
        setLastError(QStringLiteral("Please read the request first."));
        password.fill(QChar(0));
        return false;
    }

    const QJsonObject r = parseObject(modules().keystore_module.approve(handle, bundleId, password));
    password.fill(QChar(0));

    const bool ok = r.value(QStringLiteral("ok")).toBool();
    if (!ok) {
        // Deliberately generic: the keystore does not distinguish a wrong
        // password from a stale commitment, and neither should this.
        setLastError(QStringLiteral("Could not approve. Check the password and try again."));
        return false;
    }
    clearRendered();
    refresh();
    return true;
}

bool SignerUiBackend::reject(QString handle)
{
    const bool ok = modules().keystore_module.reject(handle);
    if (ok) {
        clearRendered();
    }
    refresh();
    return ok;
}

void SignerUiBackend::dismiss()
{
    clearRendered();
}

void SignerUiBackend::clearRendered()
{
    m_dwell.stop();
    setDwellElapsed(false);
    setRenderedHandle(QString());
    setRenderedBundleId(QString());
    setRenderedRequester(QString());
    setRenderLines(QStringList());
}

void SignerUiBackend::startDwell()
{
    setDwellElapsed(false);
    m_dwell.start(kDwellMs);
}
