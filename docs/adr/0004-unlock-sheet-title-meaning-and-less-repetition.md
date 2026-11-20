# ADR-0004: Unlock sheet — a real title, say what unlock does, stop repeating the rule

- Status: Accepted
- Date: 2026-11-20
- Scope: `evm_signer_ui` front-end — `qml/UnlockSheet.qml`; QML only, no backend change

## Context

Dogfooding the Unlock sheet, three things read wrong (see the operator screenshot of a keystore
wallet):

- **No hierarchy.** The title ("Unlock Hot test"), the one-line explanation, the rule line and the
  device-factor line were all the same size and weight. Nothing signalled "this is the heading" vs
  "this is the fine print", so the sheet read as an undifferentiated wall.
- **It repeated itself.** For a keystore wallet "keystore password" was stated three times: the
  sheet's *"Unlocks with its keystore password."*, the holder row's *"This device (Keystore) · Asks
  for the wallet's keystore password."* (from `StepInputs`), and the field placeholder *"Keystore
  password."* Two of those carry no new information.
- **"Unlock" was never defined, and "for every app" was misleading.** The copy said *"Unlocking it
  here unlocks it for every app…"* without saying what unlocking exposes or does. Worse, it implied
  unlocking lets any app *sign*. It does not: per `specs.md`, the default roles are `evm_keystore_ui`
  **opens and unlocks accounts**, `keystore_module` **signs**, and this plugin **approves**. Unlocking
  only makes the wallet's accounts available; an app still **requests** access ("Open it for that
  app") and **requests** each signature, each approved here. Unlock alone signs nothing.

## Decision

- **Title** uses `Theme.typography.panelTitleText` at `weightBold` — a real heading, distinct from the
  body.
- **One subtitle** states what unlock does, accurately: *"Makes this wallet's accounts available so
  apps can ask to use it. You still approve each request. It stays unlocked until you lock it or
  quit."* (Unlocked state mirrors it: *"This wallet's accounts are available to apps. You still
  approve each request…"*.) This replaces the vague "for every app" line and fixes the custody
  framing (ask-to-use, not sign).
- **Drop the duplicate rule line** for the device/keystore case: the single-way *"Unlocks with …"*
  line now shows only when the way has **no** device factor (`!takesDevice`) — a device/keystore
  factor is already spelled out by the holder row in `StepInputs`, so naming it again repeated it. A
  password-only way keeps its one-line explanation (nothing else names it).
- **Unlock / Try again become primary** (`LogosButton.Variant.Primary`), matching the "Unlock is the
  one thing to do" treatment already used on the locked `WalletCard` (ADR precedent in accountkit).

## Consequences

- Pure QML; deploy = copy `qml/` + clear qmlcache + restart. No backend change.
- The sheet now has a clear heading → explanation → action top-to-bottom, and the keystore case drops
  one redundant line (three "keystore password" mentions → two: the holder row and the field).
- The copy no longer overstates what unlocking grants, which matters for a custody surface.
- `StepInputs`' holder row is unchanged; a future pass could also hide it for a single keystore holder
  (the field label already names it), but that is out of scope here.
