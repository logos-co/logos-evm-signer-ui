# ADR-0002: Signer app header (title + subtitle) and 560 content width

- Status: Accepted
- Date: 2026-11-18
- Scope: `evm_signer_ui` front-end — `qml/SignerView.qml`, `qml/WalletsView.qml`; QML only
- Related: matches `logos-keycard-ui` (demo/keycard-improvements) app header and wallet-column width

## Context

The Signer opened with a thin header — a bold status string on the left and a Refresh button on the
right — and the Wallets tab let its cards stretch to the full window width. The Keycard app, dogfooded
alongside, reads more like a product: a large app title with a one-line subtitle and an info button,
and a wallet column capped and centred so cards don't sprawl on a wide window. We want the Signer to
match, so the two apps feel like one family.

## Decision

- **App header** (`SignerView.qml`): a 28 px **"Signer"** title with a `LogosInfoButton` ("What the
  Signer does" — it keeps unlock keys/passwords/rules and is the only surface that shows what you are
  about to sign and takes the vault password), and the secondary-text subtitle **"Signing requests and
  wallets"**. The connection status moves to the right of the title as secondary text (it was the old
  bold heading); Refresh stays beside it.
- **Content width** (`WalletsView.qml`): cap the wallet column at **560 px, centred**
  (`width: Math.min(scroll.availableWidth, 560)`, `x` centred), exactly as the Keycard app does. The
  cap also applies to the Lock-all row, the error line and the empty state, so everything aligns.
- **Drop the redundant inner "Wallets" heading**: the app title and the "Wallets" tab already name
  the tab, so the per-tab heading (which the Keycard app does not have) is removed; only the **Lock
  all** action remains, right-aligned in that row.

## Consequences

- Pure QML; deploy = copy `qml/` + clear qmlcache + restart.
- `LogosInfoButton` is a design-system control already used by other plugins; no new dependency.
- On a wide window the scrollbar sits at the far edge while the 560 column centres — same behaviour as
  the Keycard app.
