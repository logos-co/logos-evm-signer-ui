# logos-evm-signer-ui

The signing approval surface for the Logos EVM wallet.

Many modules may **request** a signature. Only this plugin may **approve** one:
[`signer_manager_module`](https://github.com/logos-co/logos-signer-manager-module)
refuses `acknowledge`/`approve`/`reject` to every other caller, and has the
account's signer (`keystore_module` for keys kept in files) sign once it approves.

It is wallet-agnostic by construction — its only REQUIRED dependency is
`signer_manager_module`, so it has no client for any wallet, chain or RPC module
and cannot be told what an intent means. It renders the lines the manager
authored, verbatim, and takes the vault password. It never unlocks an account: a
request whose account is locked can send the person to the keys app to unlock it,
on their own terms, and is read again when they come back.

It does ask one other module, optionally. `token_list_module` can say what the
address being signed to is called and how its amounts scale, and those lines
appear under the decoder's own reading of the same leg. They are a **NAME, not a
check of the code**: they cannot move the decoder's tiers, they say which list
answered — anyone who can add a custom token can put a friendly symbol on a
hostile address — and they are simply absent when no token list is loaded, which
is the ordinary case on a signing device.

It also asks `package_manager`, optionally, what the requester's installed package
calls it, so the sheet reads "Requested by: Bitcoin Wallet Core
(bitcoin_wallet_core_module)". The name is that package's `display_name`, never
anything the request says, and the id the manager gave always follows it. With no
package manager, or a name another package wears too, the id stands alone.

See `docs/specs.md` for what the approver identity does and does not assert.
