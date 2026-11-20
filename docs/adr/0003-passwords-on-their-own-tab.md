# ADR-0003: Move vault passwords to their own tab

- Status: Accepted
- Date: 2026-11-18
- Scope: `evm_signer_ui` front-end — `qml/SignerView.qml`, `qml/WalletsView.qml`, new `qml/PasswordsView.qml`; QML only, no backend change

## Context

The Wallets tab did two jobs: it listed the wallets **and** carried the whole vault-password
feature (create / rename / change / remove) stacked below the wallet cards. Dogfooding, the password
block read as an afterthought at the bottom of a scroll, mixed in with wallets it is only indirectly
related to (a password matters through a wallet's unlock *rule*, not as a wallet). With the Wallets
tab now capped to a 560 column and cleaned up (ADR-0001/0002), the passwords made it long and
double-purposed.

## Decision

Give passwords their own **"Passwords"** tab, a third tab after Requests and Wallets.

- New `PasswordsView.qml`: a self-contained view (its own `backend`, `walletsJson` parse and
  `passwords` list) holding the password list, the per-password Rename / Change / Remove controls, an
  "Add a password" form, and an empty state. Same backend calls as before
  (`createPassword` / `renamePassword` / `changePassword` / `removePassword`), same 560-centred width
  as Wallets.
- `WalletsView.qml`: the password header, list and add-form are removed; it now shows only wallets.
- `SignerView.qml`: a `LogosTabButton` "Passwords" and a `PasswordsView` added as StackLayout index 2,
  matching the tab order (Requests · Wallets · Passwords).
- Following the Wallets treatment, the redundant bold "Passwords" heading inside the tab is dropped
  (the tab names it); the explanatory line ("A password can unlock several wallets…") is kept.

## Consequences

- Pure QML; deploy = copy `qml/` + clear qmlcache + restart. No backend change.
- Passwords and wallets are now separately scrollable and independently sized; neither crowds the
  other.
- The relationship stays discoverable: a password is still chosen as a wallet's unlock rule in the
  Rule sheet (unchanged), and the Passwords tab explains what a password unlocks.
