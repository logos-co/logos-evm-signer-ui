# evm_signer_ui — specification

## What this plugin is

The single approval surface for `signer_manager_module`. Any number of modules
may call `request_approval`; only the manager's configured **approver** may
`acknowledge`, `approve` or `reject`, enforced by the manager on the platform
caller identity. The manager then has the account's signer sign: `keystore_module`
for keys kept in files, and it alone may ask the keystore to.

## Where the approver name comes from

The manager holds a **set** of approver names, a set of custodian names and the
list of signers it asks, so a terminal signer can approve *alongside* this plugin
rather than by displacing it. `signer_manager_module.configure({"approvers": […],
"custodians": […], "signers": […]})` sets them: each key takes a list of module
names, or a bare name where one is the whole answer. The call is **total**, not a
patch — a role the document does not name is held by nobody, so anything
configuring the custodians must restate the approvers and the signers in the same
call or strip them. Until something calls it the built-in defaults stand, and
this plugin is one of them: `evm_signer_ui` approves, `evm_keystore_ui` opens and
unlocks accounts, `keystore_module` signs.

## What the approver role denotes

> `evm_signer_ui` as the configured approver names a **plugin package**, not a
> person and not a process. A `ui_qml` plugin registers one identity and one
> token, shared by its QML view and its `ui-host` backend, and a callee resolves
> both to `module:evm_signer_ui`. The manager cannot distinguish the view from the
> backend and does not pretend to. What the role asserts is that **the operator
> designated this package as the code permitted to approve**. It does not assert
> that a human saw anything, and no token check can make it.
>
> And the operator is whoever called `configure` first: the call is ungated for
> now, so the role records an honest deployer's policy rather than enforcing one
> against a hostile co-resident module.

## What the split buys, and what it does not

**Buys.** No wallet — not its QML, not its backend (`eth_wallet_backend`), not the
requester `tx_sender_module`, not `eth_rpc_module`, not `railgun_module` — ever receives the vault password or
the render text, and none of them can produce a signature. A wallet's blast
radius is "can ask, and can broadcast what it is given."

**Does not buy.** In Basecamp this plugin's QML and every other plugin's QML run
in the **same process**. Each gets its own engine and sandbox, but one address
space holds both. This is a **code-authority boundary enforced by the manager's
caller check, not a process boundary** between requester and approver. Anyone
expecting the latter will be wrong.

## Rendering rules

- `renderLines` come from `signer_manager_module.acknowledge` and are displayed
  **verbatim**. The backend may not reformat, elide, truncate or re-order them,
  and the view may not derive display text from anything else.
- Every text item in the request region sets `textFormat: Text.PlainText`.
  `LogosText` is a bare `Text` with no `textFormat`, i.e. Qt's `AutoText` HTML
  autodetection, so a line containing markup would otherwise render as markup.
- Sanitisation is the **manager's** job, not the view's. It is the only party
  that parsed the intent and the only one that can tell requester-supplied text
  from its own.

## The dwell

Approve arms 500 ms after the sheet is shown, held in C++ so a QML-side edit
cannot shorten it, and re-checked in the backend before the password is used.

This defends against a click already in flight when the sheet appeared. It is
**not** protection against code that can drive the QML directly — anything
running inside the shell process can wait 500 ms. Stated here rather than
implied.

## Who signs, and what approving takes

`acknowledge` names the account's signer, what it asks for (`password`, `pin`, or `nothing` for a
device that asks the person itself) and whether an unlock covers the request. The sheet says so
in one line, in the words `evm_signer_cli` uses, so one request reads alike on both:
`Signer: keystore_module — asks for the account's password`, `— this account is unlocked: no
password`, `— confirm on the device when it asks`, or `— asks for the card's PIN`.

The password field shows only when a secret is needed, and Approve then sends an empty one. The
manager decides: an approval with no secret signs only inside an unlock that still covers the
requester, so a stale view cannot sign anything the person did not unlock. An approval a device
is still working on keeps the sheet up, reading "Confirm on the signing device", until the
manager settles it.

What was signed **without** being shown — inside an unlock the person granted that way, for
named apps only — is listed under "Signed without asking", refreshed when the manager announces
one.

## Unlocking is the keys app's

The Signer never unlocks an account. A request that needs the account's password also offers
"Unlock in the keys app…", which raises `keystore.accounts.unlock` with the request's `account`
(from `acknowledge`) and, as `app`, the module that asked; the person decides the terms there.
When the keys app answers, the request is acknowledged again if it is still on screen, so an
unlock that now covers it drops the password field. A cancel says nothing; any other refusal is
said under the link. A card's PIN, or a device that asks the person itself, gets no link.

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
