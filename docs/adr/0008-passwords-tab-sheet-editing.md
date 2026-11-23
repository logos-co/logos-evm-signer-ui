# ADR-0008: Passwords tab — add, rename, change and remove in a sheet, the Keycard way

- Status: Accepted
- Date: 2026-11-23
- Scope: `evm_signer_ui` front-end — new `qml/PasswordSheet.qml`, `qml/assets/delete.svg`;
  `qml/PasswordsView.qml`, `qml/EmptyState.qml`, `qml/SignerView.qml`. QML + one asset, no backend
  change.

## Context

The Passwords tab did its editing inline: a persistent "Add a password" block at the bottom of the
list, and Rename / Change expanding under each row as extra fields. It did not match how the Keycard
app edits a wallet — a pencil by the name, a trash on the right, and the action itself in a sheet —
and the add form sat below the list rather than above it. Three gaps:

- **Add** was a form at the foot of the tab, not a sheet with a title and an explanation.
- **Rename / Change** were inline expanders, inconsistent with the rest of the Signer (Unlock, Rule)
  and with Keycard.
- **Remove** was a bare button, and its most important question — *what happens to the wallets this
  password unlocks?* — was answered only by the button being disabled, with no explanation.

## Decision

- **One sheet for all four actions** (`PasswordSheet.qml`), over the tab like the Unlock and Rule
  sheets: a title, a one-line explanation, the inputs, then Cancel and a primary action. A `mode`
  (`add` / `rename` / `change` / `remove`) selects the copy, fields and action; the host sets the
  target password before showing it.

- **Add on top, full width; a real empty state.** The "Add password" button sits above the list at
  full column width. With no passwords, the Keycard-style centred empty state shows instead, with its
  own small "Add password" button (`EmptyState` gained an optional `actionText` / `action`).

- **Row affordances match the Keycard `WalletCard`.** Each row is: the name with a **pencil beside
  it** (rename), and on the right a **pencil** (change password) then a **trash** (remove). All three
  are `LogosIconButton { flat; size: 28; iconSize: 16 }`, coloured `textTertiary` at rest and
  brightening to `text` on hover, each with a tooltip — the same convention the wallet cards use. The
  trash glyph (`assets/delete.svg`) is filled white so the design-system colorisation tints it to the
  same tone as the pencil.

- **Remove never orphans a wallet.** The trash always opens the sheet. When the password is a
  wallet's unlock rule, the sheet is titled *"Can't remove this password yet"* and explains that those
  wallets' unlock rules must be changed to another way in first — a wallet whose only way in is this
  password would otherwise have no way to unlock — and the Remove action is withheld. Only a password
  that no wallet depends on can be removed, and then with a plain "this can't be undone" warning.

- **A gap between the tabs and the content** (`Theme.spacing.medium`), as in the Keycard app.

## Consequences

Positive:

- Editing passwords now reads the same as editing a wallet in Keycard, and the same as the Signer's
  own Unlock / Rule sheets.
- The remove flow answers the "which wallets depend on this?" question in place, and makes orphaning a
  wallet impossible from the UI.

Costs / follow-ups:

- **A failed Change shows its error on the tab, not in the sheet.** `changePassword` is the one
  password op that does not refresh wallet state, so there is no QML-observable success signal; the
  sheet closes optimistically and a wrong current password surfaces on the Passwords tab. Add / rename
  / remove close reactively on the wallet-state change and keep a failure in the sheet. Making Change
  behave the same needs a one-line backend change (refresh after `change_password`); filed as a
  follow-up rather than carried here.
- Rename and Change both use the pencil glyph, distinguished by position (beside the name vs. on the
  action line) and by tooltip / accessible name.
