# Contributing to Aixle Flow

Thank you for your interest in contributing to Aixle Flow!

## Getting Started

1. Create a new branch from `develop` for your feature or fix.
2. Make your changes following the project conventions.
3. Run the full check suite before submitting:

```bash
make check
```

## Code Quality

Before opening a PR, ensure the following pass:

| Command | Description |
|---------|-------------|
| `make lint` | Run all linters |
| `make test` | Run all tests |
| `make rubocop` | Ruby linter |
| `make eslint` | JavaScript/TypeScript linter |
| `make brakeman` | Security analysis |
| `make fsd` | Feature-Sliced Design check |

Auto-fix options are available via `make rubocop-fix` and `make eslint-fix`.

## Pull Request Guidelines

- Keep PRs focused on a single concern.
- Write descriptive commit messages.
- Ensure CI passes before requesting review.
- Reference related issues in the PR description when applicable.

## Contributor Licensing

Aixle Flow is released under the [Apache License 2.0](LICENSE). Your
contributions are accepted under that same license (inbound = outbound).

To accept a contribution we require **two** things on every pull request:

### 1. Developer Certificate of Origin (DCO)

Every commit must be signed off, certifying that you wrote the code or otherwise
have the right to submit it under the project's license. The sign-off is the
[Developer Certificate of Origin 1.1](DCO) — add it with the `-s` flag:

```bash
git commit -s -m "feat: my change"
```

This appends a `Signed-off-by: Your Name <you@example.com>` line to the commit
message. The name and email must match your real identity, and the email must be
the one you author commits with (`git config user.email`) — the check compares
them. It runs on every PR and fails if any commit is missing a sign-off or is
signed off by someone other than its author. Merge commits and commits authored
by bots are exempt.

### 2. Contributor License Agreement (CLA)

Before your first contribution can be merged, you must sign the project's
Contributor License Agreement. A bot comments on your PR with a link to the
agreement and the sentence to reply with; post that sentence as a PR comment,
exactly as given, and the bot records the signature. It is a one-time step that
covers all your future contributions. If the check does not update, comment
`recheck` to re-run it. The CLA
grants the maintainers the rights needed to distribute, sublicense, and — if
ever necessary — relicense the project, which a DCO sign-off alone does not
provide. You keep full ownership of your contributions either way.

- Contributing on your own behalf → [`CLA.md`](CLA.md) (individual)
- Contributing on behalf of an employer or other organization → your
  organization executes [`CLA-CORPORATE.md`](CLA-CORPORATE.md); see its § 7 for
  how the two interact, and note that its Schedule A is an administrative
  convenience, not a condition of the license grant

> The DCO certifies the **origin** of your contribution; the CLA grants the
> project the **rights** to it. Both are required.

Questions about contribution rights: `legal.flow@aixle.com`.
