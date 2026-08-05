# Governance

This document describes how the Aixle Flow project is governed: who makes
decisions, the roles people hold, and how those roles change over time.

> **TODO (product / maintainers):** this is a best-practice starting model
> (common for early-stage, company-backed open-source projects). Confirm it
> reflects how the team actually wants to operate, and fill in the maintainer
> list below before publishing.

## Overview

Aixle Flow is an open-source project stewarded by **Aixle**
([github.com/AixleHQ](https://github.com/AixleHQ)). The company employs the
core maintainers and sets the overall product direction; day-to-day technical
decisions are made by the maintainers in the open.

## Roles

### Users

Anyone who uses Aixle Flow. Users contribute by filing issues, joining
discussions, and helping others.

### Contributors

Anyone who contributes to the project — code, documentation, reviews, triage,
or design. No formal process: open a pull request or issue. All contributions
are subject to review, to the [Code of Conduct](CODE_OF_CONDUCT.md), and to the
contribution requirements in [CONTRIBUTING.md](CONTRIBUTING.md) (CLA and DCO).

### Maintainers

Maintainers have write access to the repository and are responsible for:

- reviewing and merging pull requests;
- triaging issues and shepherding releases;
- upholding code quality, security, and the Code of Conduct;
- mentoring contributors.

Current maintainers:

> **TODO:** list maintainers and their areas. Suggested starting set based on
> commit history — confirm before publishing:
>
> - @Artem-Petrov (or correct GitHub handle) — backend / architecture
> - @<alexandr-rozhnov-handle> — backend / platform
> - (add front-end, docs, and other area owners)
>
> Areas of ownership are also encoded in [`.github/CODEOWNERS`](.github/CODEOWNERS).

## Decision-making

We aim for **lazy consensus**: most changes are accepted if no maintainer
objects within a reasonable review window. For anything substantial:

- **Code changes** require approval from at least one maintainer (see
  [CODEOWNERS](.github/CODEOWNERS) for who reviews what). Larger or
  cross-cutting changes should be discussed in an issue first.
- **Architectural or breaking changes** are discussed openly (issue or
  discussion) and decided by maintainer consensus.
- **Product direction and roadmap** are set by Aixle in consultation with
  maintainers; the public roadmap lives in [`ROADMAP.md`](ROADMAP.md).
- If consensus cannot be reached, the maintainer group decides by simple
  majority; ties are resolved by the project lead.

## Becoming a maintainer

Contributors who have shown sustained, high-quality involvement — meaningful
PRs, reviews, issue triage, and good judgment aligned with the Code of Conduct
— may be invited to become maintainers. Any existing maintainer can nominate a
contributor; the maintainer group confirms by consensus.

Maintainers who become inactive for an extended period may move to emeritus
status (no write access, gratefully acknowledged) and can be reinstated on
return.

## Licensing and contributions

Aixle Flow is licensed under the [Apache License, Version 2.0](LICENSE) (see also
[NOTICE](NOTICE)). Contributions are accepted under the same license
(inbound = outbound).

Inbound contributions require **both**:

- a **Contributor License Agreement** — one-time and bot-mediated. Individuals sign
  the [iCLA](CLA.md); organizations execute the [cCLA](CLA-CORPORATE.md). The CLA
  secures the downstream relicensing rights the Apache 2.0 inbound license does not
  grant, while leaving contributors as the copyright owners of their work.
- a **Developer Certificate of Origin** sign-off on every commit (`git commit -s`),
  certifying the contributor has the right to submit the code under the project
  license.

Both are enforced on every pull request — see [CONTRIBUTING.md](CONTRIBUTING.md).

The project's trademarks are **not** licensed by Apache 2.0; see
[TRADEMARK.md](TRADEMARK.md). Third-party dependency licenses and the obligations
they carry are recorded in [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) and
[NOTICES.md](NOTICES.md).

## Changing this document

Changes to governance are proposed via pull request and require maintainer
consensus to merge.
