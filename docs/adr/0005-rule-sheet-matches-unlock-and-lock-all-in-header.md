# ADR-0005: Rule / New-keys sheet matches the Unlock sheet; Lock all moves to the header

- Status: Accepted
- Date: 2026-11-20
- Scope: `evm_signer_ui` front-end — `qml/RuleSheet.qml`, `qml/SignerView.qml`, `qml/WalletsView.qml`; QML only

## Context

ADR-0004 gave the Unlock sheet a real title, a one-line subtitle and a primary action. The other
modal — `RuleSheet`, which serves both **Rule…** and **New keys…** — still read flat (body-sized bold
title, no subtitle, a non-primary action), so the two sheets looked unrelated.

Separately, **Lock all** sat at the top of the Wallets tab. It is a global safety action ("lock every
unlocked wallet"), but from the Requests or Passwords tab it was out of reach, and it competed with the
wallet list for the top of the column.

## Decision

- **RuleSheet matches the Unlock sheet:** title uses `Theme.typography.panelTitleText` at `weightBold`;
  a secondary **subtitle** sits under it — for Rule, *"Choose how this wallet unlocks. Each option says
  what it gains and what it gives up."*; for New keys, the "every app gets a new key…" explanation
  (moved up from the body, where it used to float below the hidden rule list). The apply button
  ("Use this rule" / "Make new keys") is now `LogosButton.Variant.Primary`.
- **Lock all moves into the app header,** next to the (then-present) Refresh, gated on
  `anyUnlocked`; it is removed from `WalletsView`. One global place for a global action, reachable from
  any tab.

## Consequences

- Both sheets now share one shape: title → subtitle → body → primary action.
- Lock all is always reachable and no longer crowds the wallet list.
- Pure QML; deploy = copy `qml/` + clear qmlcache + restart.
