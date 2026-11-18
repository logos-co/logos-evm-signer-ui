# ADR-0001: Signer wallets adopt the shared accountkit visual pass

- Status: Accepted
- Date: 2026-11-18
- Scope: `evm_signer_ui` front-end — `qml/accountkit/*` (shared kit), `qml/WalletsView.qml`; QML only, no backend change
- Related: the same kit already carries this in `logos-keycard-ui` (demo/keycard-improvements)

## Context

The Signer's Wallets tab and the Keycard app both render wallets through the vendored
`accountkit` kit (`WalletCard.qml` + `roster.js` + `AccountDetails.qml`, all declaring the same
base `VERSION` `03f1b14`). During the Keycard UX pass the kit was edited **in place** in
`logos-keycard-ui` without bumping `VERSION`, so the two copies silently diverged: the Keycard app
got the upgraded cards while the Signer kept the pristine, flat base. Dogfooding the Signer side by
side with the Keycard app, the gap was obvious — flat hairline account rows, no icons, plain text
buttons, no visual separation between a wallet and its accounts.

## Decision

Sync the Keycard fork's `accountkit` edits forward into the Signer, and wire `WalletsView.qml` to
the new slots. Concretely:

- **Account rows become rounded, hover-highlighted cards** (`backgroundSecondary` → `backgroundTertiary`
  on hover), giving clear visual separation between a wallet and the accounts under it.
- **Icons**: a **lock glyph** before the name on a locked wallet; the wallet's name edit becomes a
  **pencil icon** beside the title (replacing the old "Names…" text button); device strips lead with
  a green status tag. New assets under `qml/assets/` (`edit.svg`, `lock.svg`).
- `fingerprint` → `walletId` + `walletIdFull`: the master fingerprint shows as the Wallet ID, with
  the seed/keyUid kept to the tooltip.
- **Unlock becomes a primary button in the locked block** (`lockedActions`), the one thing to do on a
  locked wallet, instead of a plain bottom button.
- Cleanups from live review: the redundant upper-right **"Locked" label is dropped** (the lock glyph
  already says it; only "Always unlocked" still prints, since that state is not otherwise visible),
  and the **ellipsis is removed from the "Unlock" button**.

### One intentional divergence from the Keycard copy

The Keycard card hides the edit pencil while the wallet is locked (`visible: … && !card.locked`).
The Signer must **keep the pencil available while locked**, because the Signer's *public* name is the
one shown *while* locked — you name a wallet so you can recognize it **before** unlocking. So the
Signer's copy relaxes that one guard to `visible: !!card.editAction`, with a comment marking the
divergence. This should fold back into the shared kit as an `editWhenLocked` flag (default false =
Keycard behaviour) when the kit is next unified.

## Consequences

- Pure QML; deploy = copy `qml/` + clear qmlcache + restart. No module/backend rebuild.
- The two `accountkit` copies (Keycard, Signer) now carry the same upgrade plus this one guard
  difference; neither bumped `VERSION`. The real fix is to unify the kit upstream and version it.
- `roster.js` was synced too, so Signer account labels now read as auto-names ("Ethereum 0") like the
  Keycard kit.
- **Known follow-up (not decided here):** the Signer's pencil writes the signer-manager *public* name
  via `setNames`, while the Keycard app's rename writes a **separate** local `keycard_module` store
  ("kept here without sending it on"), despite Keycard copy claiming "the Signer app included". Two
  name editors, two stores — a backend/ownership question to resolve (and a Keycard copy to correct)
  outside this UI pass.
