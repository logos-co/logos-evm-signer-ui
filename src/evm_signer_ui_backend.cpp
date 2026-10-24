#include "evm_signer_ui_backend.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QDateTime>
#include <QJsonObject>
#include <QPointer>
#include <QScopeGuard>

#include "logos_sdk.h"
#include "sheet_lines.h"
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

/// The signer module whose requests are drawn here as QR codes.
const QString kQrSigner = QStringLiteral("qr_signer_module");
/// How often a QR wallet's session is read: often while it shows or reads codes, else just enough
/// to keep the scanner's claim (fresh for 10 s) while the request awaits approval.
constexpr int kQrDrawMs = 150;
constexpr int kQrHoldMs = 3000;
/// How often a wallet's device step is read while its holder works.
constexpr int kUnlockPollMs = 400;
/// The Wallets view's backstop; events are the fast path.
constexpr int kWalletsPollMs = 3000;

QJsonObject parseObject(const QString &raw)
{
    return QJsonDocument::fromJson(raw.toUtf8()).object();
}

} // namespace

EvmSignerUiBackend::~EvmSignerUiBackend()
{
    logos_tx_decoder_free(m_decoder);
}

// Read the calldata back out of the very text on screen and decode it offline.
//
// The signer manager hands an approver `render_lines` and nothing else — no
// structured `to` or `data` — and that turns out to be the right input rather
// than a limitation: an interpretation derived from the displayed text cannot
// describe different bytes than the human is reading.
QStringList EvmSignerUiBackend::interpret(const QStringList &lines) const
{
    // A Bitcoin request is read here from the same lines; the decoder reads EVM calls only.
    std::vector<std::string> text;
    for (const QString &l : lines) {
        text.push_back(l.toStdString());
    }
    if (const std::vector<std::string> btc = sheet::bitcoinReading(text); !btc.empty()) {
        QStringList out;
        for (const std::string &l : btc) {
            out << QString::fromStdString(l);
        }
        return out;
    }

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
        // AFTER the decoder's own reading, never mixed into it: the decoder says what
        // its database can back, and this says what a token list on this device claims.
        out << tokenListLines(leg);
    }
    return out;
}

namespace {

// Which argument of a call is an amount in the token's own units, by signature.
//
// This surface's OWN table, deliberately not borrowed from the decoder: it belongs to
// the unverified layer, and a position table that travelled would invite the decoder's
// stricter promise to travel with it. A uint256 is as likely to be a deadline or a
// token id, so only the ERC-20 trio whose unit the standard itself fixes is here.
int amountArg(const QString &signature)
{
    if (signature == QStringLiteral("transfer(address,uint256)")
        || signature == QStringLiteral("approve(address,uint256)")) {
        return 1;
    }
    if (signature == QStringLiteral("transferFrom(address,address,uint256)")) {
        return 2;
    }
    return -1;
}

// Exact, never rounded — the same rule the manager's own figures follow. A value this
// cannot read scales to nothing rather than to a guess: reading 6-decimal USDC as 18 is
// wrong by a factor of a trillion, in the direction that looks harmless.
QString scaleUnits(const QString &raw, int decimals)
{
    if (raw.isEmpty() || decimals < 0 || decimals > 36) {
        return {};
    }
    for (const QChar c : raw) {
        if (!c.isDigit()) {
            return {};
        }
    }
    if (decimals == 0) {
        return raw;
    }
    const QString padded = raw.rightJustified(decimals + 1, QLatin1Char('0'));
    QString whole = padded.left(padded.size() - decimals);
    QString frac = padded.right(decimals);
    while (frac.endsWith(QLatin1Char('0'))) {
        frac.chop(1);
    }
    return frac.isEmpty() ? whole : whole + QLatin1Char('.') + frac;
}

} // namespace

QStringList EvmSignerUiBackend::tokenListLines(const QJsonObject &leg) const
{
    const QString to = leg.value(QStringLiteral("to")).toString();
    if (to.isEmpty()) {
        return {};
    }
    // Nothing to add over a VERIFIED address. The ABI database has already named it with
    // more behind the name than a list has, and a second, weaker claim beside a stronger
    // one is a question the reader has to settle rather than an answer. A token that
    // should be named with certainty belongs in that database, not here.
    if (leg.value(QStringLiteral("confidence")).toString() == QStringLiteral("verified")) {
        return {};
    }

    // Absence is reported, not asked about: the wrapper has no `available()`, and a
    // missing optional dependency surfaces here as a call error. Bounded at 2s because
    // this runs while a human waits at the sheet — the default is 20s, and a token list
    // that cannot answer must cost the naming rather than the approval.
    const QJsonArray want{ to };
    logos::CallError err;
    const QString raw = modules().token_list_module.get_tokens_by_address(
        leg.value(QStringLiteral("chainId")).toInt(),
        QString::fromUtf8(QJsonDocument(want).toJson(QJsonDocument::Compact)),
        &err,
        Timeout(2000));
    if (!err.ok()) {
        return {};
    }
    const QJsonObject reply = parseObject(raw);
    if (!reply.value(QStringLiteral("ok")).toBool()) {
        return {};
    }
    const QJsonArray tokens = reply.value(QStringLiteral("tokens")).toArray();
    if (tokens.isEmpty()) {
        return {};
    }
    const QJsonObject t = tokens.first().toObject();
    const QString symbol = t.value(QStringLiteral("symbol")).toString();
    if (symbol.isEmpty()) {
        return {};
    }
    const QString name = t.value(QStringLiteral("name")).toString();
    const QString source = t.value(QStringLiteral("source")).toString(QStringLiteral("unknown"));
    const QString named = (name.isEmpty() || name == symbol)
                              ? symbol
                              : QStringLiteral("%1 (%2)").arg(symbol, name);

    // Worded exactly as evm_signer_cli words it: the same request read on the two
    // surfaces must say the same thing.
    QStringList out{ QStringLiteral(
        "Token list (%1) says this address is %2 — a NAME, not a check of the code.")
                         .arg(source, named) };

    const int idx = amountArg(
        leg.value(QStringLiteral("function")).toObject().value(QStringLiteral("signature")).toString());
    const QJsonArray args = leg.value(QStringLiteral("args")).toArray();
    if (idx >= 0 && idx < args.size()) {
        const QString scaled = scaleUnits(
            args.at(idx).toObject().value(QStringLiteral("value")).toString(),
            t.value(QStringLiteral("decimals")).toInt(-1));
        if (!scaled.isEmpty()) {
            // Hedged: the argument's POSITION comes from the signature the decoder
            // matched, which may itself be a selector guess.
            out << QStringLiteral("  If that reading is right, the amount is %1 %2.")
                       .arg(scaled, symbol);
        }
    }
    return out;
}

void EvmSignerUiBackend::nameRequester(const QString &handle, const QString &module)
{
    if (module.isEmpty()) {
        return;
    }
    // What the user installed, never the request. Asked without waiting: the id shows at once, the
    // name joins it when package_manager answers, and with none installed nothing waits at all.
    QPointer<EvmSignerUiBackend> self(this);
    modules().package_manager.getInstalledPackagesAsyncResult(
        [self, handle, module](logos::AsyncResult<QVariantList> res) {
            if (!self || !res.error.ok()) {
                return;
            }
            std::vector<std::pair<std::string, std::string>> installed;
            for (const QVariant &p : res.value) {
                const QVariantMap m = p.toMap();
                installed.emplace_back(m.value(QStringLiteral("name")).toString().toStdString(),
                                       m.value(QStringLiteral("displayName")).toString().toStdString());
            }
            const QString name = QString::fromStdString(sheet::installedName(module.toStdString(), installed));
            QMetaObject::invokeMethod(self, [self, handle, module, name] {
                // Only onto the request it was asked for, if that is still the one on screen.
                if (self && self->renderedHandle() == handle && self->renderedRequester() == module) {
                    self->setRenderedRequesterName(name);
                }
            }, Qt::QueuedConnection);
        },
        Timeout(2000));
}

void EvmSignerUiBackend::onContextReady()
{
    // Null on failure, and that is survivable: every other property is
    // unaffected and the sheet still renders the manager's lines.
    m_decoder = logos_tx_decoder_new();

    m_dwell.setSingleShot(true);
    QObject::connect(&m_dwell, &QTimer::timeout, [this] { setDwellElapsed(true); });
    QObject::connect(&m_poll, &QTimer::timeout, [this] { refresh(); });
    QObject::connect(&m_qrPoll, &QTimer::timeout, [this] { qrPoll(); });

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
    modules().signer_manager_module.onApproval_offered([this](QString) { refreshSoon(); });
    modules().signer_manager_module.onApproval_settled([this](QString handle, QString state) {
        if (handle == renderedHandle()) {
            clearRendered();
        }
        // Relayed so the view can end an intent it is holding for this handle. The manager's
        // event is the only place that sees EVERY way a request ends -- this sheet, the
        // queue by hand, or a surface that is not this one -- and an intent answered from a
        // button instead would stay open whenever the human took another route.
        emit settled(handle, state);
        refreshSoon();
    });
    // Signed unseen, inside an unlock the person granted that way: re-read the list, off the IPC stack.
    modules().signer_manager_module.onSigned_without_asking([this](QString) {
        QTimer::singleShot(0, this, [this] { refreshUnattended(); });
    });
    // A device plugged in or out: the request on screen may now be signed by another, off the IPC stack.
    modules().signer_manager_module.onAccounts_changed([this](int) {
        QTimer::singleShot(0, this, [this] {
            refreshSigners();
            refreshWallets();
        });
    });
    // A wallet added, unlocked, locked or changed anywhere, and an open waiting for consent or
    // ended: read the Wallets view again, off the IPC stack.
    modules().signer_manager_module.onWallets_changed([this](QString) {
        QTimer::singleShot(0, this, [this] { refreshWallets(); });
    });
    modules().signer_manager_module.onWallets_locked([this](int) {
        QTimer::singleShot(0, this, [this] { refreshWallets(); });
    });
    modules().signer_manager_module.onAccess_requested([this](QString) {
        QTimer::singleShot(0, this, [this] { refreshWallets(); });
    });
    modules().signer_manager_module.onAccess_settled([this](QString handle, QString state) {
        QTimer::singleShot(0, this, [this, handle, state] {
            if (parseObject(openJson()).value(QStringLiteral("handle")).toString() == handle) {
                setOpenJson(QStringLiteral("{}"));
            }
            emit openSettled(handle, state);
            refreshWallets();
        });
    });

    QObject::connect(&m_unlockPoll, &QTimer::timeout, [this] { unlockPoll(); });
    QObject::connect(&m_walletsPoll, &QTimer::timeout, [this] { refreshWallets(); });
    m_walletsPoll.start(kWalletsPollMs);
    m_poll.start(kPollMs);
    refresh();
    refreshUnattended();
    refreshWallets();
    setStatusText(QStringLiteral("Ready"));
}

void EvmSignerUiBackend::refreshUnattended()
{
    const QJsonObject reply = parseObject(modules().signer_manager_module.unattended_signatures());
    if (reply.value(QStringLiteral("ok")).toBool()) {
        const QJsonArray signedUnseen = reply.value(QStringLiteral("signed")).toArray();
        setUnattendedJson(QString::fromUtf8(QJsonDocument(signedUnseen).toJson(QJsonDocument::Compact)));
    }
}

void EvmSignerUiBackend::refreshSoon()
{
    QTimer::singleShot(0, this, [this] { refresh(); });
}

void EvmSignerUiBackend::refresh()
{
    // pending() is synchronous and can block for as long as its timeout. The
    // poll timer must not stack a second one behind a call that is still in
    // flight, or every tick adds another 20s of queued work.
    if (m_inFlight) {
        return;
    }
    m_inFlight = true;
    const auto done = qScopeGuard([this] { m_inFlight = false; });

    const QJsonObject reply = parseObject(modules().signer_manager_module.pending());
    if (!reply.value(QStringLiteral("ok")).toBool()) {
        // Distinguish "the manager refused us" from "we never reached the
        // manager". Collapsing the two is not a cosmetic sin: a transport
        // timeout reported as "not the approver" sends whoever reads it hunting
        // an authorization problem that does not exist. The manager's own
        // refusal is the exact string "not authorized"; anything else here --
        // an empty reply, a timeout, unparseable JSON -- is the call failing.
        const QString err = reply.value(QStringLiteral("error")).toString();
        if (err == QStringLiteral("not authorized")) {
            setLastError(QStringLiteral(
                "This build is not registered as the approver, so it cannot show "
                "or approve signing requests."));
            setStatusText(QStringLiteral("Not the approver"));
        } else {
            setLastError(QStringLiteral("Could not reach the signer manager%1")
                             .arg(err.isEmpty() ? QStringLiteral(".")
                                                : QStringLiteral(": %1").arg(err)));
            setStatusText(QStringLiteral("Signer manager unreachable"));
        }
        m_errors.pollFailed(lastError().toStdString());
        return;
    }
    if (m_errors.pollRead(lastError().toStdString())) {
        setLastError(QString());
    }
    const QJsonArray items = reply.value(QStringLiteral("pending")).toArray();
    setPendingJson(QString::fromUtf8(QJsonDocument(items).toJson(QJsonDocument::Compact)));
    // A confirmation outlives the next poll. Without this the "Approved — …"
    // line survives for under a second before the 1s queue poll overwrites it
    // with "Nothing to approve", so the one message the human actually waited
    // for is the one they never see. It holds the LINE only: a request that
    // arrives meanwhile is claimed below, and ends the hold.
    const bool holding = m_confirmUntil.isValid() && QDateTime::currentDateTimeUtc() < m_confirmUntil;
    // While a device waits for its person, its line stays until the manager settles the request.
    if (!holding && !renderedSigning()) {
        setStatusText(items.isEmpty() ? QStringLiteral("Nothing to approve")
                                      : QStringLiteral("%1 waiting").arg(items.size()));
    }

    // Acknowledge receipt automatically.
    //
    // `acknowledge` means "this approver has the request on screen", NOT "the
    // human decided" — the manager drops an offer nobody claims within a minute,
    // and after the claim there is deliberately no deadline at all, because a
    // person is reading. Waiting for a click here would put that timer on a
    // human, which is exactly the deadline the design says must not exist.
    //
    // Only ever one at a time: the manager keeps at most one record Rendered
    // (claiming another demotes the previous), and that single Rendered record
    // is what binds the text a human read to the approval they then give. So
    // claim the head of the queue and leave the rest Offered; a requester that
    // re-offers gets picked up as soon as this one is decided.
    if (renderedHandle().isEmpty() && !items.isEmpty()) {
        const QString next = items.first().toObject()
                                  .value(QStringLiteral("handle")).toString();
        if (!next.isEmpty() && acknowledge(next) && holding) {
            m_confirmUntil = QDateTime();
            setStatusText(QStringLiteral("%1 waiting").arg(items.size()));
        }
    }
}

bool EvmSignerUiBackend::acknowledge(QString handle)
{
    const QJsonObject r = parseObject(modules().signer_manager_module.acknowledge(handle));
    if (!r.value(QStringLiteral("ok")).toBool()) {
        clearRendered();
        setLastError(r.value(QStringLiteral("error")).toString(QStringLiteral("could not open that request")));
        return false;
    }

    // Verbatim. The manager is the only party that parsed the intent, so it is
    // the only one that can tell requester-supplied text from its own — this
    // backend must not "improve" any of it.
    QStringList lines;
    for (const QJsonValue &v : r.value(QStringLiteral("render_lines")).toArray()) {
        lines << v.toString();
    }
    // The requester's own claim about the bundle, which the manager keeps in a
    // SEPARATE list. Dropping it hid the one line saying what the signature is
    // claimed to be for, leaving the human to approve a commitment and a digest.
    // It is never merged into `lines`: the split is the only thing that lets the
    // view mark requester-supplied text as such without parsing it.
    QStringList claims;
    for (const QJsonValue &v : r.value(QStringLiteral("claim_lines")).toArray()) {
        claims << v.toString();
    }

    setLastError(QString());
    setClaimLines(claims);
    // A name belongs to one request: gone before another's id shows, and asked for again below.
    if (r.value(QStringLiteral("handle")).toString() != renderedHandle()) {
        setRenderedRequesterName(QString());
    }
    setRenderedRequester(r.value(QStringLiteral("requester")).toString());
    setRenderedBundleId(r.value(QStringLiteral("bundle_id")).toString());
    setClaimLines(claims);
    setRenderLines(lines);
    setInterpretationLines(interpret(lines));
    applySigner(r);
    setRenderedHandle(r.value(QStringLiteral("handle")).toString());
    nameRequester(renderedHandle(), renderedRequester());
    startDwell();
    return true;
}

// acknowledge, choose_signer and approval_signers answer alike; only the signer part is read here,
// since choosing a signer changes nothing about what is signed.
void EvmSignerUiBackend::applySigner(const QJsonObject &r)
{
    setRenderedSigner(r.value(QStringLiteral("signer")).toString());
    setRenderedCollects(r.value(QStringLiteral("collects")).toString());
    setRenderedUnlocked(r.value(QStringLiteral("unlocked")).toBool());
    setRenderedAccount(r.value(QStringLiteral("account")).toString());
    setRenderedSignersJson(QString::fromUtf8(
        QJsonDocument(r.value(QStringLiteral("signers")).toArray()).toJson(QJsonDocument::Compact)));
    setRenderedSignerExplicit(r.value(QStringLiteral("explicit")).toBool());
    if (renderedSigner() == kQrSigner) {
        qrClaim();
    } else if (!qrUnlocking()) {
        qrRelease();
    }
}

bool EvmSignerUiBackend::chooseSigner(QString handle, QString signer)
{
    if (handle.isEmpty() || handle != renderedHandle() || renderedSigning()) {
        setLastError(QStringLiteral("That is not the request on screen."));
        return false;
    }
    if (signer == renderedSigner()) {
        return true;
    }
    const QJsonObject r = parseObject(
        modules().signer_manager_module.choose_signer(handle, renderedBundleId(), signer));
    if (!r.value(QStringLiteral("ok")).toBool()) {
        setLastError(r.value(QStringLiteral("error")).toString(QStringLiteral("Could not sign with that signer.")));
        return false;
    }
    setLastError(QString());
    applySigner(r);
    return true;
}

void EvmSignerUiBackend::refreshSigners()
{
    QString presence;
    if (readSigners(&presence)
        && m_errors.signersRead(lastError().toStdString(), renderedSigner().toStdString(), presence.toStdString())) {
        setLastError(QString());
    }
}

bool EvmSignerUiBackend::readSigners(QString *presence)
{
    if (renderedHandle().isEmpty() || renderedSigning()) {
        return false;
    }
    const QJsonObject r = parseObject(modules().signer_manager_module.approval_signers(renderedHandle()));
    if (!r.value(QStringLiteral("ok")).toBool() || r.value(QStringLiteral("handle")).toString() != renderedHandle()) {
        return false;
    }
    applySigner(r);
    for (const QJsonValue &v : r.value(QStringLiteral("signers")).toArray()) {
        if (v.toObject().value(QStringLiteral("signer")).toString() == renderedSigner()) {
            *presence = v.toObject().value(QStringLiteral("presence")).toString();
        }
    }
    return true;
}

bool EvmSignerUiBackend::approve(QString handle, QString bundleId, QString password)
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

    const QJsonObject r = parseObject(modules().signer_manager_module.approve(handle, bundleId, password));
    password.fill(QChar(0));

    const bool ok = r.value(QStringLiteral("ok")).toBool();
    if (ok && r.value(QStringLiteral("state")).toString() == QStringLiteral("signing")) {
        // A device signs in its own time; the manager's settled event ends the sheet.
        setLastError(QString());
        setRenderedSigning(true);
        if (!m_qrHandle.isEmpty()) {
            setStatusText(QStringLiteral("Show the codes to your QR wallet"));
            m_qrPoll.start(kQrDrawMs);
            qrPoll();
        } else {
            setStatusText(QStringLiteral("Confirm on the signing device"));
        }
        return true;
    }
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
        // records the outcome. The manager has already settled the record, so
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
        // By code: the manager's own reason where no password would help, never "check the password".
        const QString code = r.value(QStringLiteral("code")).toString();
        const QString why = r.value(QStringLiteral("error")).toString();
        const bool device = why.contains(QStringLiteral("connect")) || why.contains(QStringLiteral("no longer offers"));
        if (code == QStringLiteral("signer_changed") || code == QStringLiteral("unsupported")
            || code == QStringLiteral("refused") || (code == QStringLiteral("unavailable") && device)) {
            setLastError(why);
        } else if (code == QStringLiteral("unavailable")) {
            setLastError(QStringLiteral("The signer did not answer. Try again."));
        } else {
            setLastError(QStringLiteral("Could not approve. Check the password and try again."));
        }
        // A device that went away, or a default that moved: show who would sign now, and keep
        // the reason up until that signer is back or another one is chosen.
        if (code == QStringLiteral("signer_changed") || code == QStringLiteral("unavailable")) {
            QString presence;
            readSigners(&presence);
            m_errors.signerRefused(lastError().toStdString(), renderedSigner().toStdString(), presence.toStdString());
        }
        return false;
    }
    clearRendered();
    refresh();
    return true;
}

bool EvmSignerUiBackend::reject(QString handle)
{
    const bool ok = modules().signer_manager_module.reject(handle);
    if (ok) {
        clearRendered();
    }
    refresh();
    return ok;
}

void EvmSignerUiBackend::dismiss()
{
    clearRendered();
}

void EvmSignerUiBackend::qrClaim()
{
    if (m_qrHandle.isEmpty()) {
        // Where the scanner isn't installed, or won't have this app draw, the answer is no handle:
        // a QR wallet's request then shows in the scanner's own window, as before.
        const QString h = modules().qr_scanner_module.presenter_attach();
        if (!h.startsWith(QStringLiteral("prs_"))) {
            return;
        }
        m_qrHandle = h;
        m_qrFramesId.clear();
    }
    m_qrPoll.start(renderedSigning() || qrUnlocking() ? kQrDrawMs : kQrHoldMs);
}

void EvmSignerUiBackend::qrRelease()
{
    m_qrPoll.stop();
    setQrJson(QStringLiteral("{}"));
    setQrFramesJson(QStringLiteral("[]"));
    m_qrFramesId.clear();
    if (m_qrHandle.isEmpty()) {
        return;
    }
    // Called from the manager's settled event too, which runs on the IPC read stack: a call out
    // from there deadlocks its own reply, so the scanner is let go from a clean stack.
    const QString h = m_qrHandle;
    m_qrHandle.clear();
    QTimer::singleShot(0, this, [this, h] { modules().qr_scanner_module.presenter_detach(h); });
}

void EvmSignerUiBackend::qrPoll()
{
    if (m_qrHandle.isEmpty() || m_qrInFlight) {
        return;
    }
    m_qrInFlight = true;
    const auto done = qScopeGuard([this] { m_qrInFlight = false; });
    QJsonObject v = parseObject(modules().qr_scanner_module.presenter_view(m_qrHandle, m_qrFramesId));
    if (!v.value(QStringLiteral("ok")).toBool()) {
        // The claim lapsed (a long stall) or the scanner went: claim again on the next read.
        m_qrHandle.clear();
        qrClaim();
        return;
    }
    if (v.contains(QStringLiteral("frames"))) {
        setQrFramesJson(QString::fromUtf8(
            QJsonDocument(v.value(QStringLiteral("frames")).toArray()).toJson(QJsonDocument::Compact)));
        m_qrFramesId = v.value(QStringLiteral("frames_id")).toString();
        v.remove(QStringLiteral("frames"));
    }
    v.remove(QStringLiteral("ok"));
    setQrJson(QString::fromUtf8(QJsonDocument(v).toJson(QJsonDocument::Compact)));
}

bool EvmSignerUiBackend::qrPress()
{
    if (m_qrHandle.isEmpty()) {
        return false;
    }
    const bool pressed = modules().qr_scanner_module.presenter_press(m_qrHandle) == QStringLiteral("pressed");
    qrPoll();
    return pressed;
}

bool EvmSignerUiBackend::qrCancel()
{
    if (m_qrHandle.isEmpty()) {
        return false;
    }
    // The wallet's session ends; the QR signer then refuses the job, and the manager's settled
    // event ends the sheet as for any other outcome.
    const QJsonObject r = parseObject(modules().qr_scanner_module.presenter_cancel(m_qrHandle));
    qrPoll();
    return r.value(QStringLiteral("cancelled")).toBool();
}

void EvmSignerUiBackend::clearRendered()
{
    setLastError(QString());
    // A QR wallet's unlock drawn here keeps its codes: they are not this request's.
    if (!qrUnlocking()) {
        qrRelease();
    }
    m_dwell.stop();
    setDwellElapsed(false);
    setRenderedHandle(QString());
    setRenderedBundleId(QString());
    setRenderedRequester(QString());
    setRenderedRequesterName(QString());
    setRenderedSigner(QString());
    setRenderedCollects(QString());
    setRenderedUnlocked(false);
    setRenderedAccount(QString());
    setRenderedSignersJson(QStringLiteral("[]"));
    setRenderedSignerExplicit(false);
    setRenderedSigning(false);
    setClaimLines(QStringList());
    setRenderLines(QStringList());
    setClaimLines(QStringList());
    // Must clear with the rest: a reading left behind would describe a request
    // that is no longer on screen.
    setInterpretationLines(QStringList());
}

void EvmSignerUiBackend::startDwell()
{
    setDwellElapsed(false);
    m_dwell.start(kDwellMs);
}

// ── Wallets ─────────────────────────────────────────────────────────────────

namespace {

QString compact(const QJsonObject &o)
{
    return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
}

QString compact(const QJsonArray &a)
{
    return QString::fromUtf8(QJsonDocument(a).toJson(QJsonDocument::Compact));
}

/// The manager's own words where it gave them: they name the wallet or the password.
QString walletErrorText(const QJsonObject &r, const QString &fallback)
{
    const QString why = r.value(QStringLiteral("error")).toString();
    if (why == QStringLiteral("not authorized")) {
        return QStringLiteral("This build is not registered as the approver, so it cannot unlock or change wallets.");
    }
    return why.isEmpty() ? fallback : why;
}

} // namespace

bool EvmSignerUiBackend::walletReply(const QString &reply, const QString &fallback)
{
    const QJsonObject r = parseObject(reply);
    if (!r.value(QStringLiteral("ok")).toBool()) {
        setWalletError(walletErrorText(r, fallback));
        return false;
    }
    setWalletError(QString());
    return true;
}

void EvmSignerUiBackend::refreshWallets()
{
    if (m_walletsInFlight) {
        return;
    }
    m_walletsInFlight = true;
    const auto done = qScopeGuard([this] { m_walletsInFlight = false; });

    QJsonObject w = parseObject(modules().signer_manager_module.wallet_settings());
    if (!w.value(QStringLiteral("ok")).toBool()) {
        setWalletError(walletErrorText(w, QStringLiteral("Could not read the wallets.")));
        return;
    }
    w.remove(QStringLiteral("ok"));
    setWalletsJson(compact(w));
    const QJsonObject r = parseObject(modules().signer_manager_module.roster());
    if (r.value(QStringLiteral("ok")).toBool()) {
        setRosterJson(compact(r.value(QStringLiteral("accounts")).toArray()));
    }
    const QJsonObject q = parseObject(modules().signer_manager_module.access_requests());
    if (q.value(QStringLiteral("ok")).toBool()) {
        QJsonArray opens;
        for (const QJsonValue &v : q.value(QStringLiteral("requests")).toArray()) {
            if (v.toObject().value(QStringLiteral("kind")).toString() == QStringLiteral("open")) {
                opens.append(v);
            }
        }
        setOpensJson(compact(opens));
    }
}

bool EvmSignerUiBackend::qrUnlocking() const
{
    const QJsonObject u = parseObject(unlockJson());
    return u.value(QStringLiteral("state")).toString() == QStringLiteral("device")
           && u.value(QStringLiteral("holder")).toString() == kQrSigner;
}

bool EvmSignerUiBackend::beginStep(const QString &method, const QString &seed, const QString &holder, QJsonObject body,
                                   QString secret, QString passwordsJson)
{
    const auto wipe = qScopeGuard([&] {
        secret.fill(QChar(0));
        passwordsJson.fill(QChar(0));
    });
    if (parseObject(unlockJson()).value(QStringLiteral("state")).toString() == QStringLiteral("device")) {
        setWalletError(QStringLiteral("Finish or cancel the step under way first."));
        return false;
    }
    // The holder asked, so the app knows whether to draw a QR wallet's codes: the person's pick,
    // else the wallet's first.
    QString asked = holder;
    if (asked.isEmpty()) {
        for (const QJsonValue &v : parseObject(walletsJson()).value(QStringLiteral("wallets")).toArray()) {
            const QJsonObject w = v.toObject();
            if (w.value(QStringLiteral("seed")).toString() == seed) {
                asked = w.value(QStringLiteral("holders")).toArray().first().toObject().value(QStringLiteral("signer")).toString();
            }
        }
    }
    body.insert(QStringLiteral("seed"), seed);
    if (!holder.isEmpty()) {
        body.insert(QStringLiteral("holder"), holder);
    }
    if (!secret.isEmpty()) {
        body.insert(QStringLiteral("secret"), secret);
    }
    const QJsonObject passwords = QJsonDocument::fromJson(passwordsJson.toUtf8()).object();
    if (!passwords.isEmpty()) {
        body.insert(QStringLiteral("passwords"), passwords);
    }
    QString params = compact(body);
    QString reply;
    if (method == QStringLiteral("set_rule")) {
        reply = modules().signer_manager_module.set_rule(params);
    } else if (method == QStringLiteral("change_keys")) {
        reply = modules().signer_manager_module.change_keys(params);
    } else {
        reply = modules().signer_manager_module.unlock_wallet(params);
    }
    params.fill(QChar(0));
    const QJsonObject r = parseObject(reply);
    if (!r.value(QStringLiteral("ok")).toBool()) {
        setWalletError(walletErrorText(r, QStringLiteral("That did not work. Try again.")));
        refreshWallets();
        return false;
    }
    setWalletError(QString());
    if (r.value(QStringLiteral("state")).toString() == QStringLiteral("device")) {
        const QJsonObject step{
            { QStringLiteral("handle"), r.value(QStringLiteral("handle")).toString() },
            { QStringLiteral("seed"), seed },
            { QStringLiteral("holder"), asked },
            { QStringLiteral("method"), method },
            { QStringLiteral("state"), QStringLiteral("device") },
            { QStringLiteral("step"), QStringLiteral("working") },
        };
        setUnlockJson(compact(step));
        if (asked == kQrSigner) {
            qrClaim();
        }
        m_unlockPoll.start(kUnlockPollMs);
        unlockPoll();
        return true;
    }
    endStep(seed, true);
    return true;
}

void EvmSignerUiBackend::unlockPoll()
{
    QJsonObject u = parseObject(unlockJson());
    const QString handle = u.value(QStringLiteral("handle")).toString();
    if (handle.isEmpty() || u.value(QStringLiteral("state")).toString() != QStringLiteral("device")) {
        m_unlockPoll.stop();
        return;
    }
    const QJsonObject p = parseObject(modules().signer_manager_module.unlock_progress(handle));
    if (!p.value(QStringLiteral("ok")).toBool()) {
        u.insert(QStringLiteral("state"), QStringLiteral("failed"));
        u.insert(QStringLiteral("error"), QStringLiteral("The signer manager no longer knows this step."));
        setUnlockJson(compact(u));
        endStep(u.value(QStringLiteral("seed")).toString(), false);
        return;
    }
    for (const QString &k : { QStringLiteral("state"), QStringLiteral("step"), QStringLiteral("code"), QStringLiteral("error") }) {
        if (p.contains(k) && !p.value(k).isNull()) {
            u.insert(k, p.value(k));
        } else if (k != QStringLiteral("state")) {
            u.remove(k);
        }
    }
    setUnlockJson(compact(u));
    const QString state = u.value(QStringLiteral("state")).toString();
    if (state == QStringLiteral("device")) {
        return;
    }
    m_unlockPoll.stop();
    if (state == QStringLiteral("needs_password")) {
        // The device answered; only a password is typed again, so its codes are done here.
        if (renderedSigner() != kQrSigner) {
            qrRelease();
        }
        return;
    }
    endStep(u.value(QStringLiteral("seed")).toString(), state == QStringLiteral("done"));
}

void EvmSignerUiBackend::endStep(const QString &seed, bool ok)
{
    m_unlockPoll.stop();
    if (renderedSigner() != kQrSigner) {
        qrRelease();
    }
    if (ok) {
        setUnlockJson(QStringLiteral("{}"));
    } else {
        // Kept for the sheet to say why, without a handle: nothing more happens to it.
        QJsonObject u = parseObject(unlockJson());
        u.remove(QStringLiteral("handle"));
        u.insert(QStringLiteral("state"), QStringLiteral("failed"));
        setUnlockJson(compact(u));
    }
    emit unlockEnded(seed, ok);
    refreshWallets();
}

bool EvmSignerUiBackend::unlockWallet(QString seed, QString way, QString holder, QString secret, QString passwordsJson)
{
    const QJsonObject body{ { QStringLiteral("way"), way } };
    return beginStep(QStringLiteral("unlock_wallet"), seed, holder, body, secret, passwordsJson);
}

bool EvmSignerUiBackend::setRule(QString seed, QString waysJson, QString holder, QString secret, QString passwordsJson)
{
    const QJsonObject body{ { QStringLiteral("ways"), QJsonDocument::fromJson(waysJson.toUtf8()).array() } };
    return beginStep(QStringLiteral("set_rule"), seed, holder, body, secret, passwordsJson);
}

bool EvmSignerUiBackend::changeKeys(QString seed, bool newIndex, QString holder, QString secret, QString passwordsJson)
{
    const QJsonObject body{ { QStringLiteral("newIndex"), newIndex } };
    return beginStep(QStringLiteral("change_keys"), seed, holder, body, secret, passwordsJson);
}

bool EvmSignerUiBackend::retryUnlock(QString passwordsJson)
{
    const auto wipe = qScopeGuard([&] { passwordsJson.fill(QChar(0)); });
    QJsonObject u = parseObject(unlockJson());
    const QString handle = u.value(QStringLiteral("handle")).toString();
    if (handle.isEmpty() || u.value(QStringLiteral("state")).toString() != QStringLiteral("needs_password")) {
        setWalletError(QStringLiteral("Nothing is waiting for a password."));
        return false;
    }
    const QJsonObject body{
        { QStringLiteral("handle"), handle },
        { QStringLiteral("passwords"), QJsonDocument::fromJson(passwordsJson.toUtf8()).object() },
    };
    QString params = compact(body);
    const QJsonObject r = parseObject(modules().signer_manager_module.unlock_wallet(params));
    params.fill(QChar(0));
    if (r.value(QStringLiteral("ok")).toBool()) {
        setWalletError(QString());
        endStep(u.value(QStringLiteral("seed")).toString(), true);
        return true;
    }
    if (r.value(QStringLiteral("code")).toString() == QStringLiteral("wrong_secret")) {
        u.insert(QStringLiteral("error"), r.value(QStringLiteral("error")).toString());
        setUnlockJson(compact(u));
        return false;
    }
    u.insert(QStringLiteral("error"), walletErrorText(r, QStringLiteral("The unlock did not finish.")));
    setUnlockJson(compact(u));
    endStep(u.value(QStringLiteral("seed")).toString(), false);
    return false;
}

bool EvmSignerUiBackend::cancelUnlock()
{
    const QJsonObject u = parseObject(unlockJson());
    const QString handle = u.value(QStringLiteral("handle")).toString();
    if (!handle.isEmpty()) {
        modules().signer_manager_module.cancel_unlock(handle);
    }
    m_unlockPoll.stop();
    if (renderedSigner() != kQrSigner) {
        qrRelease();
    }
    setUnlockJson(QStringLiteral("{}"));
    if (!handle.isEmpty()) {
        emit unlockEnded(u.value(QStringLiteral("seed")).toString(), false);
    }
    return true;
}

bool EvmSignerUiBackend::lockWallets(QString seedsJson)
{
    const QJsonArray seeds = QJsonDocument::fromJson(seedsJson.toUtf8()).array();
    QJsonObject body;
    if (!seeds.isEmpty()) {
        body.insert(QStringLiteral("seeds"), seeds);
    }
    const bool ok = walletReply(modules().signer_manager_module.lock_wallets(compact(body)),
                                QStringLiteral("Could not lock."));
    refreshWallets();
    return ok;
}

bool EvmSignerUiBackend::setNames(QString seed, QString name, QString privateName)
{
    QJsonObject body{ { QStringLiteral("seed"), seed }, { QStringLiteral("privateName"), privateName } };
    if (!name.trimmed().isEmpty()) {
        body.insert(QStringLiteral("name"), name);
    }
    const bool ok = walletReply(modules().signer_manager_module.set_names(compact(body)),
                                QStringLiteral("Could not rename the wallet."));
    refreshWallets();
    return ok;
}

QString EvmSignerUiBackend::createPassword(QString name, QString password)
{
    QString params = compact(QJsonObject{ { QStringLiteral("name"), name }, { QStringLiteral("password"), password } });
    password.fill(QChar(0));
    const QJsonObject r = parseObject(modules().signer_manager_module.create_password(params));
    params.fill(QChar(0));
    refreshWallets();
    if (!r.value(QStringLiteral("ok")).toBool()) {
        setWalletError(walletErrorText(r, QStringLiteral("Could not add the password.")));
        return QString();
    }
    setWalletError(QString());
    return r.value(QStringLiteral("id")).toString();
}

bool EvmSignerUiBackend::renamePassword(QString id, QString name)
{
    const QJsonObject body{ { QStringLiteral("id"), id }, { QStringLiteral("name"), name } };
    const bool ok = walletReply(modules().signer_manager_module.rename_password(compact(body)),
                                QStringLiteral("Could not rename the password."));
    refreshWallets();
    return ok;
}

bool EvmSignerUiBackend::changePassword(QString id, QString oldPassword, QString newPassword)
{
    QString params = compact(QJsonObject{
        { QStringLiteral("id"), id }, { QStringLiteral("old"), oldPassword }, { QStringLiteral("new"), newPassword } });
    oldPassword.fill(QChar(0));
    newPassword.fill(QChar(0));
    const bool ok = walletReply(modules().signer_manager_module.change_password(params),
                                QStringLiteral("Could not change the password."));
    params.fill(QChar(0));
    return ok;
}

bool EvmSignerUiBackend::removePassword(QString id)
{
    const bool ok = walletReply(modules().signer_manager_module.remove_password(compact(QJsonObject{ { QStringLiteral("id"), id } })),
                                QStringLiteral("Could not remove the password."));
    refreshWallets();
    return ok;
}

bool EvmSignerUiBackend::showOpen(QString handle)
{
    QJsonObject r = parseObject(modules().signer_manager_module.acknowledge_access(handle));
    if (!r.value(QStringLiteral("ok")).toBool()) {
        setOpenJson(QStringLiteral("{}"));
        setWalletError(walletErrorText(r, QStringLiteral("Could not show that request.")));
        return false;
    }
    r.remove(QStringLiteral("ok"));
    setWalletError(QString());
    setOpenJson(compact(r));
    return true;
}

bool EvmSignerUiBackend::consentOpen(QString handle, QString bundleId, QString group)
{
    QJsonObject body{ { QStringLiteral("handle"), handle }, { QStringLiteral("bundle_id"), bundleId } };
    if (!group.isEmpty()) {
        body.insert(QStringLiteral("group"), group);
    }
    const bool ok = walletReply(modules().signer_manager_module.approve_access(compact(body)),
                                QStringLiteral("Could not open the wallet."));
    if (ok) {
        setOpenJson(QStringLiteral("{}"));
    }
    refreshWallets();
    return ok;
}

bool EvmSignerUiBackend::rejectOpen(QString handle)
{
    const bool ok = modules().signer_manager_module.reject_access(handle);
    setOpenJson(QStringLiteral("{}"));
    refreshWallets();
    return ok;
}
