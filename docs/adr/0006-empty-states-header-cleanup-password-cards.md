# ADR-0006: Shared empty-state, a quieter header, and passwords as cards

- Status: Accepted
- Date: 2026-11-20
- Scope: `evm_signer_ui` front-end — new `qml/EmptyState.qml`; `qml/SignerView.qml`,
  `qml/WalletsView.qml`, `qml/PasswordsView.qml`; QML only, no backend change

## Context

Three presentation gaps, dogfooding:

- **Empty states read as stray lines.** "No signing requests are waiting." and "No wallets yet…" were
  single left-aligned lines at the top of an otherwise blank page — they looked like an error, not a
  calm empty state. The Keycard app already has a nicer pattern (a centred bold title + a secondary
  explanation).
- **The header carried a redundant status line and a Refresh button.** "Nothing to approve" duplicated
  what the empty state now says, and Refresh called `backend.refresh()` — but the backend already
  **polls every second** (`kPollMs`) and refreshes on every manager event (`onApproval_offered`,
  `onApproval_settled`, `onWallets_changed`, `onWallets_locked`, `onAccounts_changed`). The view is
  never more than ~1s stale on its own, so the manual button bought nothing.
- **Passwords were bare rows.** Each password was a line of text plus buttons, visually unlike the
  wallet cards beside them in the same app.

## Decision

- **A shared `EmptyState` component** (centred bold `subtitleText` title + a wrapped `textSecondary`
  description, capped at 420, horizontally centred via an anchor so it does not drift), matching the
  Keycard app. Used by the Requests and Wallets tabs. (The Passwords tab always shows an "Add a
  password" form, so it is never a blank page and keeps its inline line.)
- **Drop the header status line and Refresh.** The header is now just the title and **Lock all**.
  "Connecting…" still shows while the backend is coming up. Re-scanning is automatic (poll + events).
- **Passwords as cards:** each password is a `backgroundMuted` block with a border and radius, a bold
  **title** (its name) and a **secondary line** (*"Unlocks N wallets"* / *"Not a wallet's unlock rule
  yet"*), with Rename / Change / Remove on the right — the wallet-card shape.

## Consequences

- One empty-state style across the app, aligned with Keycard; empty tabs read as deliberate.
- A quieter header; no manual refresh to reach for, because the view already keeps itself current. If
  a future change removes the poll, the button (or an explicit refresh-on-focus) should come back.
- Passwords and wallets now read as the same kind of object.
- Pure QML; deploy = copy `qml/` + clear qmlcache + restart.
