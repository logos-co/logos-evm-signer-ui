# ADR-0009: A failed password change stays in its sheet

- Status: Accepted
- Date: 2026-11-23
- Scope: `evm_signer_ui` front-end — `qml/PasswordSheet.qml`, `qml/PasswordsView.qml`. QML only.
- Closes: the follow-up in ADR-0008

## Context

ADR-0008 left one gap: Change password closed its sheet as soon as it was pressed, because
`changePassword`, unlike add / rename / remove, doesn't refresh the wallet settings the sheet watches
for. A wrong current password then showed its error on the Passwords tab behind a closed sheet, and the
person had to reopen it and type everything again. The tab's own error line also kept showing the
shared `walletError` after the sheet was cancelled, and errors from other tabs.

## Decision

- Change waits for `changePassword`'s own answer with `logos.watch`, as `RuleSheet` does for
  `createPassword`: it closes only when the change worked. On a failure the sheet stays open, shows the
  error, and clears the typed passwords to retype. No backend change.
- The Passwords tab drops its error line: every password action happens in the sheet, which shows its
  own error.

## Consequences

- A wrong current password is reported where it was typed, once.
- Verified by hand: a wrong current password kept the sheet open with the error only in it; the right
  one closed it; Cancel left no error on the tab.
