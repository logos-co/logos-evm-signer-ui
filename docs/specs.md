# signer_ui — specification

## What this plugin is

The single approval surface for `keystore_module`. Any number of modules may
call `request_approval`; only `signer_ui` may `acknowledge`, `approve` or
`reject`, enforced by the keystore on the platform caller identity.

## What the Tier A allowlist entry denotes

> `signer_ui` in the keystore's allowlist names a **plugin package**, not a
> person and not a process. A `ui_qml` plugin registers one identity and one
> token, shared by its QML view and its `ui-host` backend, and a callee resolves
> both to `module:signer_ui`. The keystore cannot distinguish the view from the
> backend and does not pretend to. What the entry asserts is that **the operator
> designated this package as the code permitted to approve**. It does not assert
> that a human saw anything, and no token check can make it.

## What the split buys, and what it does not

**Buys.** No wallet — not its QML, not its backend, not `wallet_backend_module`,
not `eth_rpc_module`, not `railgun_module` — ever receives the vault password or
the render text, and none of them can produce a signature. A wallet's blast
radius is "can ask, and can broadcast what it is given."

**Does not buy.** In Basecamp this plugin's QML and every other plugin's QML run
in the **same process**. Each gets its own engine and sandbox, but one address
space holds both. This is a **code-authority boundary enforced by the keystore's
caller check, not a process boundary** between requester and approver. Anyone
expecting the latter will be wrong.

## Rendering rules

- `renderLines` come from `keystore_module.acknowledge` and are displayed
  **verbatim**. The backend may not reformat, elide, truncate or re-order them,
  and the view may not derive display text from anything else.
- Every text item in the request region sets `textFormat: Text.PlainText`.
  `LogosText` is a bare `Text` with no `textFormat`, i.e. Qt's `AutoText` HTML
  autodetection, so a line containing markup would otherwise render as markup.
- Sanitisation is the **keystore's** job, not the view's. It is the only party
  that parsed the intent and the only one that can tell requester-supplied text
  from its own.

## The dwell

Approve arms 500 ms after the sheet is shown, held in C++ so a QML-side edit
cannot shorten it, and re-checked in the backend before the password is used.

This defends against a click already in flight when the sheet appeared. It is
**not** protection against code that can drive the QML directly — anything
running inside the shell process can wait 500 ms. Stated here rather than
implied.

## What the backend must never do

Persist the password, log it, place it in a PROP, or emit it in an event. It
holds the password only for the duration of the `approve` call and wipes its
copy afterwards.

## Known gaps

- **No autoload.** If this plugin is not open, `request_approval` still succeeds
  and the record waits — but nothing shows it. If the user also closes the
  requesting tab, the system stays correct and becomes silent. A shell attention
  channel is the fix and is not in this repo.
- **No OS-level modality.** The plugin root is a `QQuickItem`, so the sheet is
  modal within its own tab, not always-on-top.
