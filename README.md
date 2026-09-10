# logos-evm-signer-ui

The signing approval surface for the Logos EVM wallet.

Many modules may **request** a signature. Only this plugin may **approve** one:
`keystore_module` refuses `acknowledge`/`approve`/`reject` to every other caller.

It is wallet-agnostic by construction — its only REQUIRED dependency is
`keystore_module`, so it has no client for any wallet, chain or RPC module and
cannot be told what an intent means. It renders the lines the keystore authored,
verbatim, and takes the vault password.

It does ask one other module, optionally. `token_list_module` can say what the
address being signed to is called and how its amounts scale, and those lines
appear under the decoder's own reading of the same leg. They are a **NAME, not a
check of the code**: they cannot move the decoder's tiers, they say which list
answered — anyone who can add a custom token can put a friendly symbol on a
hostile address — and they are simply absent when no token list is loaded, which
is the ordinary case on a signing device.

See `docs/specs.md` for what the approver identity does and does not assert.
