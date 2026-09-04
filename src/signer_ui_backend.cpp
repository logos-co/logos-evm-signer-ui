#include "signer_ui_backend.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QDateTime>
#include <QJsonObject>
#include <QScopeGuard>

#include "logos_sdk.h"
#include "tx_decoder.h"

namespace {

/// How long the sheet must have been up before Approve arms. Cheap protection
/// against a click that was already in flight when the sheet appeared; it is
/// NOT protection against an attacker who can drive the QML directly, and the
/// docs say so rather than implying otherwise.
constexpr int kDwellMs = 500;

/// The queue backstop. Events are the fast path.
constexpr int kPollMs = 1000;

/// How long an "Approved" confirmation survives the queue poll.
constexpr int kConfirmSeconds = 30;

QJsonObject parseObject(const QString &raw)
{
    return QJsonDocument::fromJson(raw.toUtf8()).object();
}

} // namespace

SignerUiBackend::~SignerUiBackend()
{
    logos_tx_decoder_free(m_decoder);
}

// Read the calldata back out of the very text on screen and decode it offline.
//
// The keystore hands an approver `render_lines` and nothing else — no
// structured `to` or `data` — and that turns out to be the right input rather
// than a limitation: an interpretation derived from the displayed text cannot
// describe different bytes than the human is reading.
QStringList SignerUiBackend::interpret(const QStringList &lines) const
{
    if (!m_decoder || lines.isEmpty()) {
        return {};
    }

    QJsonArray in;
    for (const QString &l : lines) {
        in.append(l);
    }
    char *raw = logos_tx_decoder_describe_render_lines(
        m_decoder, QJsonDocument(in).toJson(QJsonDocument::Compact).constData());
    if (!raw) {
        return {};
    }
    const QJsonObject r = parseObject(QString::fromUtf8(raw));
    logos_tx_decoder_string_free(raw);

    const QJsonArray legs = r.value(QStringLiteral("legs")).toArray();
    if (!r.value(QStringLiteral("ok")).toBool() || legs.isEmpty()) {
        return {};
    }

    // Label by ITEM count, not by how many decoded. A request of one message
    // and one transaction decodes to a single leg, and an unlabelled reading of
    // it would look like a description of the whole request.
    const bool label = r.value(QStringLiteral("items")).toInt() > 1;

    QStringList out;
    for (const QJsonValue &v : legs) {
        const QJsonObject leg = v.toObject();
        if (label) {
            out << QStringLiteral("Item [%1]:").arg(leg.value(QStringLiteral("index")).toInt());
        }
        for (const QJsonValue &line : leg.value(QStringLiteral("lines")).toArray()) {
            out << line.toString();
        }
    }
    return out;
}

void SignerUiBackend::onContextReady()
{
    // Null on failure, and that is survivable: every other property is
    // unaffected and the sheet still renders the keystore's lines.
    m_decoder = logos_tx_decoder_new();

    m_dwell.setSingleShot(true);
    QObject::connect(&m_dwell, &QTimer::timeout, [this] { setDwellElapsed(true); });
    QObject::connect(&m_poll, &QTimer::timeout, [this] { refresh(); });

    // Subscribe FIRST, then reconcile. The other order loses any request
    // created between the snapshot and the subscription becoming live; this
    // order can only ever produce a duplicate, which the queue de-dupes by
    // handle.
    //
    // Arming subscriptions here is the documented pattern: onContextReady fires
    // when ui-host has handed this plugin its LogosAPI, so the typed dependency
    // surface is live. module-builder's ui-typed-backend example does exactly
    // this.
    // An event callback runs ON THE IPC READ STACK. A synchronous outbound call
    // made from here re-enters that stack and blocks the very thread that would
    // deliver its reply, so the call cannot complete and dies on its timeout --
    // measured as "keystore_module.pending timed out after 20000ms", repeatedly,
    // while the events themselves arrived perfectly well. Hop to the event loop
    // first so the call runs on a clean stack.
    //
    // Note this is about EVENT CALLBACKS specifically. onContextReady is a
    // normal place to call out from and needs no such treatment -- that is the
    // documented pattern, and arming these subscriptions from there is fine.
    modules().keystore_module.onApproval_offered([this](QString) { refreshSoon(); });
    modules().keystore_module.onApproval_settled([this](QString handle, QString state) {
        if (handle == renderedHandle()) {
            clearRendered();
        }
        // Relayed so the view can end an intent it is holding for this handle. The keystore
        // event is the only place that sees EVERY way a request ends -- this sheet, the
        // queue by hand, or a surface that is not this one -- and an intent answered from a
        // button instead would stay open whenever the human took another route.
        emit settled(handle, state);
        refreshSoon();
    });

    m_poll.start(kPollMs);
    refresh();
    setStatusText(QStringLiteral("Ready"));
}

void SignerUiBackend::refreshSoon()
{
    QTimer::singleShot(0, this, [this] { refresh(); });
}

void SignerUiBackend::refresh()
{
    // pending() is synchronous and can block for as long as its timeout. The
    // poll timer must not stack a second one behind a call that is still in
    // flight, or every tick adds another 20s of queued work.
    if (m_inFlight) {
        return;
    }
    m_inFlight = true;
    const auto done = qScopeGuard([this] { m_inFlight = false; });

    const QJsonObject reply = parseObject(modules().keystore_module.pending());
    if (!reply.value(QStringLiteral("ok")).toBool()) {
        // Distinguish "the keystore refused us" from "we never reached the
        // keystore". Collapsing the two is not a cosmetic sin: a transport
        // timeout reported as "not the approver" sends whoever reads it hunting
        // an authorization problem that does not exist. The keystore's own
        // refusal is the exact string "not authorized"; anything else here --
        // an empty reply, a timeout, unparseable JSON -- is the call failing.
        const QString err = reply.value(QStringLiteral("error")).toString();
        if (err == QStringLiteral("not authorized")) {
            setLastError(QStringLiteral(
                "This build is not registered as the approver, so it cannot show "
                "or approve signing requests."));
            setStatusText(QStringLiteral("Not the approver"));
        } else {
            setLastError(QStringLiteral("Could not reach the keystore%1")
                             .arg(err.isEmpty() ? QStringLiteral(".")
                                                : QStringLiteral(": %1").arg(err)));
            setStatusText(QStringLiteral("Keystore unreachable"));
        }
        return;
    }
    setLastError(QString());
    const QJsonArray items = reply.value(QStringLiteral("pending")).toArray();
    setPendingJson(QString::fromUtf8(QJsonDocument(items).toJson(QJsonDocument::Compact)));
    // A confirmation outlives the next poll. Without this the "Approved — …"
    // line survives for under a second before the 1s queue poll overwrites it
    // with "Nothing to approve", so the one message the human actually waited
    // for is the one they never see.
    if (m_confirmUntil.isValid() && QDateTime::currentDateTimeUtc() < m_confirmUntil) {
        return;
    }
    setStatusText(items.isEmpty() ? QStringLiteral("Nothing to approve")
                                  : QStringLiteral("%1 waiting").arg(items.size()));

    // Acknowledge receipt automatically.
    //
    // `acknowledge` means "this approver has the request on screen", NOT "the
    // human decided" — the keystore gives an approver only ACK_DEADLINE (3s)
    // to claim an offer, and after the claim there is deliberately no deadline
    // at all, because a person is reading. Waiting for a click here would put
    // a 3-second timer on a human, which is exactly the deadline the design
    // says must not exist: every request would expire before it could be read.
    //
    // Only ever one at a time: the keystore keeps at most one record Rendered
    // (claiming another demotes the previous), and that single Rendered record
    // is what binds the text a human read to the approval they then give. So
    // claim the head of the queue and leave the rest Offered; a requester that
    // re-offers gets picked up as soon as this one is decided.
    if (renderedHandle().isEmpty() && !items.isEmpty()) {
        const QString next = items.first().toObject()
                                  .value(QStringLiteral("handle")).toString();
        if (!next.isEmpty()) {
            acknowledge(next);
        }
    }
}

bool SignerUiBackend::acknowledge(QString handle)
{
    const QJsonObject r = parseObject(modules().keystore_module.acknowledge(handle));
    if (!r.value(QStringLiteral("ok")).toBool()) {
        setLastError(r.value(QStringLiteral("error")).toString(QStringLiteral("could not open that request")));
        clearRendered();
        return false;
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
    setInterpretationLines(interpret(lines));
    setRenderedHandle(r.value(QStringLiteral("handle")).toString());
    startDwell();
    return true;
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
    if (ok) {
        // Confirm what was authorised. approve() answers with a COUNT, never the
        // signatures — the approver causes them to exist and never sees them,
        // because only the requester can collect them with its receipt. Showing
        // the count is the most this surface can honestly report, and a human
        // who just typed a vault password deserves to be told it worked.
        const int n = r.value(QStringLiteral("signed_count")).toInt();
        setStatusText(n == 1 ? QStringLiteral("Approved — 1 item signed")
                             : QStringLiteral("Approved — %1 items signed").arg(n));
        m_confirmUntil = QDateTime::currentDateTimeUtc().addSecs(kConfirmSeconds);

        // Drop the approved request from the queue HERE, in the same slot that
        // records the outcome. The keystore has already settled the record, so
        // this only says what is now true -- but saying it now is what makes it
        // reliable: the refresh() below can be swallowed whole by the m_inFlight
        // guard if a poll is already blocked inside pending(), and a pending()
        // that fails or times out returns without touching the queue at all.
        // That left an approved request on screen for up to one 20s RPC
        // deadline, long after the human was told it was signed.
        QJsonArray rest;
        const QJsonArray shown = QJsonDocument::fromJson(pendingJson().toUtf8()).array();
        for (const QJsonValue &v : shown) {
            if (v.toObject().value(QStringLiteral("handle")).toString() != handle) {
                rest.append(v);
            }
        }
        setPendingJson(QString::fromUtf8(QJsonDocument(rest).toJson(QJsonDocument::Compact)));
    }
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
    // Must clear with the rest: a reading left behind would describe a request
    // that is no longer on screen.
    setInterpretationLines(QStringList());
}

void SignerUiBackend::startDwell()
{
    setDwellElapsed(false);
    m_dwell.start(kDwellMs);
}
