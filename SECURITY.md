# Security policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's
private vulnerability reporting instead: on this repository, go to
**Security → Report a vulnerability**.

You will get an answer within a few days. Please include steps to
reproduce and the affected version.

## Scope

Of particular interest:
- the encrypted sync (key handling, NIP-44 encryption, pairing via QR),
- storage of API keys and the sync key on the device,
- backup files and restore,
- anything that could make a machine heat or brew unintentionally.

## Supported versions

Only the latest release receives security fixes.
