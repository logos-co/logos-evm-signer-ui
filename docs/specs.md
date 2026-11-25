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

## The surface

- **Header:** the "Signer" title with an info button ("What the Signer does"), the subtitle
  "Signing requests and wallets", and **Lock all**, so a global action is reachable from every tab.
  "Connecting…" shows while the backend comes up. There is no Refresh: the backend polls every
  second (`kPollMs`) and refreshes on every manager event, so the view keeps itself current. If the
  poll goes, a refresh has to come back.
- **Tabs:** Requests · Wallets · Passwords. The Wallets and Passwords columns are capped at 560 and
  centred, as in the Keycard app.
- **Status line:** the top of the Requests tab shows the backend's `statusText` only when it says
  something the person waits for: an approval's outcome ("Approved — 3 items signed", which the
  backend holds past the next poll), a device at work, or the manager out of reach. The routine
  "Ready", "Nothing to approve" and "N waiting" stay hidden, since the tab count and the queue say
  them.
- **Empty states:** an empty tab shows `EmptyState` (a centred title, one line of explanation and
  an optional button) instead of a stray line: "No signing requests", "No wallets yet", "No
  passwords yet".
- **Sheets:** Unlock, Rule / New keys and Password sheets share one shape: a bold title, one line
  that says what the action does, the inputs, then Cancel and one primary action.
- **App icon:** `src/icons/signer.png` is full-bleed (256×256, opaque to the edges, the keyhole on
  black as on the Keycard tile), and Basecamp masks it to the tile shape.

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

## Who asked

Section 1 names the requester by the id `acknowledge` gives as `requester`: the caller's module
name, as the platform identified it ("Requested by: bitcoin_wallet_core_module"). Nothing in the
heading comes from the request: the requester's `purpose` stays in the section's body.

## Section 3 for a Bitcoin request

The decoder reads EVM calls only. For a Bitcoin request the backend adds up section 2's own lines
instead: what goes back to this wallet (which the manager checked), what is paid out, the fee and
the inputs. The first line says where the figures came from, the second what the send does:

```
Interpreted: Bitcoin — section 2's own figures, added up on this device
  Everything comes back to this wallet; you pay only the 141-sat fee.
```

or `Sends 0.00003000 BTC to an address not shown to be this wallet's; 0.00363024 BTC comes back to
this wallet; fee 141 sats.` "Not shown to be this wallet's" is all the manager's lines say of a
payment: it proves only the outputs the PSBT claims for this wallet. A line the backend does not
know, or figures that do not add up to the inputs, give one line instead: section 2 is the signer
manager's whole reading of this Bitcoin transaction.

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
in one line, naming the signer as "Sign with" below does, and by its module id only when the
manager doesn't list it: `Signs with: This device (Keystore) — asks for the account's password`,
`— no password needed for this request`, `— confirm on the device when it asks`, or `— asks for
the card's PIN`. `evm_signer_cli`'s `signer:` line keeps the module id.

When several signers hold the account (the keystore, a Keycard in a reader, a Keycard Shell over
USB, a QR wallet), the line becomes "Sign with": one row per signer, in the manager's order.
- Each row says whether the signer is ready, connected or not connected, and how it signs: by
  password or PIN, on the device, or with codes shown here. A QR wallet is never called
  connected: it needs no connection.
- The person may choose any signer that can take the request. `chooseSigner` tells the manager,
  whose answer, not the click, says who signs. The request and its commitment stay the same, so
  there is no second reading. Only the secret below changes, and a typed one is cleared.
- A row that can't be chosen says why: not connected, or the manager's reason it can't take this
  request, such as a bare digest on a device that shows what it signs.
- When the manager announces that accounts changed, the rows are read again (`approval_signers`).
  At Approve, a chosen device that went away, or a default that moved, is the manager's own
  message, never "check the password". The request stays on screen, and so does the message,
  until that signer is back, another one is chosen, an approval goes through, or the request
  leaves. The queue poll clears only an error it set itself.

The password field shows only when a secret is needed, and Approve then sends an empty one. The
manager decides: an approval with no secret signs only inside an unlock that still covers the
requester, so a stale view cannot sign anything the person did not unlock. An approval a device
is still working on keeps the sheet up, reading "Confirm on the signing device", with Approve
disabled and a line saying the request stays until the device answers. The manager's settle
event ends it.

Not while the QR signer is unreleased: `qr_scanner_module` is not a dependency then, so no claim
is held and a QR wallet's request shows in the scanner's own window. With the dependency back, a
QR wallet's request (signer `qr_signer_module`) is drawn here instead of in a window of the
scanner's:
- While it is on screen, the backend holds `qr_scanner_module`'s presenter claim. That module is an
  optional dependency, and the core naming this app as the caller is what lets it draw sessions.
  The wallet's session then starts with no window.
- Once approved, `qrJson` and `qrFramesJson` carry what the scanner's `presenter_view` answers.
  The sheet draws the codes in turn, dark on white with their quiet zone, under the hint and a
  button for the next step ("Scan the answer", then "Show the request again"). While the camera
  reads, it says whether a code is in view and how many parts are read. No picture comes here.
- Cancel ends the wallet's session, which ends the request. So does Back, rather than leave the
  camera waiting.
- A session that started in the scanner's window before this app held the claim stays there, and
  the sheet says so.
- The claim is let go when the request settles, however it settles, or leaves the screen.

What was signed **without** being shown — inside an unlock the person granted that way, for
named apps only — is listed under "Signed without asking", refreshed when the manager announces
one.

## Wallets: unlocked here, once per session

A wallet is a seed, whichever signers hold it: the keystore, a Keycard, a Shell, a QR wallet. Its
data in every module is encrypted under keys the signer manager derives from that seed's key, and
the person unlocks it here, once, for every app, until they lock it or quit. The **Wallets** tab
lists every wallet from the manager's `wallet_settings`: its public name, and its private name
once unlocked; its holders; how it unlocks; its accounts once unlocked (from `roster`, by
`seed`); and the apps waiting to open it (`access_requests`, by `seed`).

The Signer is **read-only about the wallets themselves** (decided 2026-11-24): a wallet is renamed
or removed only in the app that holds it (Keys, Keycard, QR Wallets), and each card says which
("Rename or remove it in the Keycard app."). Device setup stays there too. Here a wallet is only
unlocked, locked, given its rule and given new keys.

Each wallet is [logos-account-kit](https://github.com/logos-co/logos-account-kit)'s
`WalletCard`, as in the Keycard and Keys apps. `qml/accountkit` is the kit at the commit its
`VERSION` names, byte for byte (CI runs the kit's `scripts/check.sh`), so anything Signer-specific
lives in `WalletsView.qml` and the card's properties, never in the vendored folder:
- its **Wallet ID** is the master fingerprint its accounts carry (`wallet.fingerprint`), with the
  seed in its tooltip;
- each account row shows its name (an unnamed one by family and number, "Bitcoin 0"), a Bitcoin
  account's script type and network as tags, its derivation path, and its address: an EVM
  account's own, or a Bitcoin account's first receiving address (0/0), from the roster's
  `firstAddress`;
- a locked wallet shows neither, since its accounts aren't in `roster` until it unlocks; a lock
  glyph sits before its name and **Unlock** is its primary action. Only "Always unlocked" is
  printed as a state, since nothing else shows it;
- the Signer passes no edit or trash icon and no rename action, so neither the card nor its rows
  offer to rename or remove.

- **The Unlock sheet** is titled with the wallet's name and says what unlocking does: the
  accounts become available for apps to ask for, and each request is still approved here. It
  offers the wallet's ways in and asks for what the chosen one takes:
  - which holder to ask when it takes the device;
  - the card's PIN, or the keystore's password;
  - nothing for a Shell, which asks the person itself;
  - a QR round trip drawn here, as for signing;
  - each named password, by the name the person gave it.

  With one way in, a line names it ("Unlocks with the device and the password “Home”.") unless
  it is the device alone, which the holder row already names; so a way that takes a password keeps
  that password's name on screen once its field is typed into.

  `unlock_wallet` either settles at once or starts a device step, which `unlock_progress`
  follows. When the device answered but a password didn't match, the sheet asks for the password
  again without the device (`retryUnlock`). Closing the sheet while the device works cancels the
  step.
- **An app's open** is shown in the sheet beside its wallet, in the manager's lines, verbatim.
  "Open it for that app" is the person's consent (`approve_access` without a password), armed
  only once the wallet is unlocked; "Refuse" rejects it. While it waits the sheet has no Close,
  only a device step's Cancel. An open that names no wallet lists the unlocked wallets' accounts
  of the family asked for, and the person picks one.
- **Rules.** "Rule…" offers:
  - the device only;
  - the device and a password;
  - the device, or a password alone;
  - for a wallet whose holders give no unlock key, a password alone;
  - for any wallet, always unlocked: no protection, open from the start, and no Lock. Moving it
    back to a protected rule gives it new keys.

  Each says what it gains and what it gives up. A keystore wallet's "device" is its own keystore
  password. A new way that takes the device asks the device again, and a new password is made
  before the rule that takes it.
- **Passwords** are the Signer's own, on their own tab. They are named, can unlock several
  wallets, and are added, renamed, changed and removed here. Each is a card: its name with a pencil
  (rename), and on the right a pencil (change) and a trash (remove); **Add password** sits above
  the list, or in the empty state. Every action happens in a sheet that waits for the backend's own
  answer: only a success clears and closes it, and a failure keeps what was typed and shows the
  error in the sheet. The sheet's fields are cleared whenever it hides, and leaving the tab closes
  it, so nothing typed stays in a hidden field. The trash always opens the sheet: a password a rule
  still takes isn't removed, and the sheet says which rules to change first.
- **New keys** wrap every way in again, so they need each way's factors. For a wallet a QR wallet
  holds, an option also moves to the device's next unlock key, for when the QR answer may have been
  photographed. It isn't offered otherwise: a card's, a Shell's or the keystore's answer never
  leaves this computer, and whoever could read it here could read the next one too.
- **Lock** locks one wallet, **Lock all** every wallet. Lock all is armed only while a wallet a
  lock would close is unlocked: an always-unlocked wallet stays open whatever is locked, so it
  doesn't count.
- **`wallets.unlock`** (`{ seeds?, signer?, openHandle? }`) opens the sheet for the wallet an open names,
  else for each locked one of `seeds`, or each locked wallet when it names none, one after another
  in the wallets' order. It is answered `ok` once the last unlocks (or, with an open, once the open
  settles approved), `ok` too when the person closes the sheet after unlocking at least one, and
  `cancelled` when they close it having unlocked none; a second ask displaces the first. **Skip**
  leaves the wallet on screen locked and goes on to the next, for one whose device is not at hand.
  `seeds` are the signer manager's ids, or, with `signer`, that signer's own names for its seeds, as
  its holder entries carry them (the keystore's app asks for the keystore's locked wallets so). Seeds
  that name no wallet are answered `bad_request`.

Passwords and PINs cross from this QML to this backend for the same reason the vault password does:
the two are one trust unit, and only the backend talks to the manager. The backend sends them in
one call and wipes its copies.

## Signing without a password is not offered

The Signer never unlocks an account for signing, and no longer sends the person to the keys app to
do it: "unlock" here means a wallet's data, in Wallets. The manager's unlock is still there for a
custodian to grant (the e2e's probe does); a request it covers shows no password field, and the
signer line says no password is needed.

## What the backend must never do

Persist the password, log it, place it in a PROP, or emit it in an event. It
holds the password only for the duration of the `approve` call and wipes its
copy afterwards.

## Known gaps

- **Two name stores.** The Signer shows the manager's public and private names but no longer edits
  them (the backend's `setNames` stays, unused by the view). The Keycard app's rename writes its
  own store, so a rename there doesn't reach the Signer until the owning apps write the manager's
  names.
- **No autoload.** If this plugin is not open, `request_approval` still succeeds
  and the record waits — but nothing shows it. If the user also closes the
  requesting tab, the system stays correct and becomes silent. A shell attention
  channel is the fix and is not in this repo.
- **No OS-level modality.** The plugin root is a `QQuickItem`, so the sheet is
  modal within its own tab, not always-on-top.
