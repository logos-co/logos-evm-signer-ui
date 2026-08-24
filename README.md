# logos-evm-signer-ui

The signing approval surface for the Logos EVM wallet.

Many modules may **request** a signature. Only this plugin may **approve** one:
`keystore_module` refuses `acknowledge`/`approve`/`reject` to every other caller.

It is wallet-agnostic by construction — its only dependency is `keystore_module`,
so it has no client for any wallet, chain, RPC or token-list module and cannot
decode an intent. It renders the lines the keystore authored, verbatim, and
takes the vault password.

See `docs/specs.md` for what the approver identity does and does not assert.
