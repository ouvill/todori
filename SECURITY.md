# Security Policy

Todori is a pre-release E2EE Todo application. Security reports are welcome, especially when they concern encryption, key handling, authentication, local storage, synchronization, or release infrastructure.

## Supported Versions

Todori has not reached its first stable release yet. Until the first stable release is published, security fixes are applied to the `main` branch only.

Released version support will be documented here once stable releases exist.

## Reporting a Vulnerability

Please do not report security vulnerabilities in public GitHub issues, pull requests, discussions, or comments.

This repository is public, and the preferred reporting path is GitHub private vulnerability reporting. Use the "Report a vulnerability" button on the Security tab and include:

- a short description of the issue and affected component;
- the expected security impact;
- reproduction steps or proof-of-concept details, if available;
- affected platform or environment;
- whether the issue is already public or known to others.

If GitHub private vulnerability reporting cannot be used, do not publish vulnerability details in a public issue or pull request. Open a minimal public issue only to say that the private reporting channel is unavailable, without technical details, so maintainers can restore a private path.

## Scope

Security reports for the following areas are in scope:

- E2EE design and implementation, including record encryption, associated data, and server-visible metadata.
- Key derivation, versioned key wrapping, key-generation rotation, Device Key capsules, Recovery Key handling, Master Key handling, device certificates, Safety numbers, and X25519 / ML-KEM / ML-DSA key material.
- OPAQUE registration, login, password change, account recovery, session handling, and device revocation.
- SQLCipher local database encryption, local database key derivation, tenant database separation, and local data exposure risks.
- Synchronization protocol behavior, authorization, tenant isolation, server-side metadata handling, tombstones, history retention, and replay or ordering issues.
- Server-side control plane data, including wrapped keys, device metadata, organization membership, and subscription-gated synchronization access.
- CI, build scripts, generated artifacts, release packaging, and dependency or supply-chain issues that could affect shipped binaries.

Todori's Organization sharing is not considered release-ready until authenticated device certificates, mandatory Safety number verification, and per-device hybrid X25519 + ML-KEM-768 key delivery have passed independent review. A security review performed by the implementation team is not described as an external audit.

## Out of Scope

The following should be reported through normal GitHub issues once issues are enabled:

- general bugs without a security impact;
- feature requests or product feedback;
- non-security crashes or UI glitches;
- documentation typos that do not affect security guidance;
- speculative reports without a plausible security impact.

Please do not perform destructive testing, denial-of-service testing, social engineering, spam, or testing against systems you do not own or have permission to assess.

## Disclosure

Todori is not currently promising a bug bounty, fixed response SLA, legal safe harbor, or public advisory timeline. Those policies require maintainer and legal review before they can be offered.

The maintainers intend to coordinate fixes privately before public disclosure. Once an issue is fixed, an advisory or release note may summarize the impact and remediation without publishing exploit details that would put users at unnecessary risk.
