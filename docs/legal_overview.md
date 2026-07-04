# Legal and Open Source Overview

This document summarizes Todori's public legal and open source posture. Internal operating notes, pre-release review checklists, and rough legal drafts are maintained outside the public repository.

## Open Source Posture

Todori is intended to be developed in public so that its privacy and end-to-end encryption claims can be inspected by users, contributors, and security reviewers.

The repository uses:

- `AGPL-3.0-only` as the public source license.
- A Contributor License Agreement for external contributions.
- Public technical documentation for cryptography, storage, sync boundaries, and build/test behavior.

The AGPL license and CLA are meant to keep the project inspectable while preserving the maintainer's ability to distribute official builds through common app distribution channels.

## Privacy and Terms Direction

Todori's user-facing privacy and terms documents should reflect the product's technical design:

- The server should receive only the minimum account and service metadata needed to operate the product.
- End-to-end encrypted content must remain unreadable to the server.
- Users must be told clearly when data cannot be recovered because required secrets were lost.
- Account deletion and data removal flows should be designed before a broad public release.
- Liability language should be realistic and reviewed before formal launch.

Formal privacy policy and terms documents are separate release-preparation artifacts.

## Distribution Readiness

Before public launch or app distribution, Todori should complete the ordinary compliance and platform checks required for an app that includes cryptography, paid features, and user accounts. Public documents should describe user-facing behavior and technical guarantees, while private working notes may track provider forms, review steps, and unresolved operating details.

## Brand and Project Identity

The project name is Todori. Public material should use the name consistently and avoid implying that final app-store availability, support commitments, or commercial terms exist before they are actually ready.

## Non-Public Detail

The following information belongs in the private repository unless intentionally generalized for public release:

- maintainer operating details that are not required for users or contributors
- pre-release platform registration notes and account setup details
- provider-specific legal or compliance checklists
- raw drafts of terms, privacy policy, or review notes
- name availability research and launch-planning notes
- unresolved risk notes that would be misleading or unsafe without context
