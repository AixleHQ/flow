# Contributing to Aixle App

Thank you for your interest in contributing to Aixle App!

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

### Developer Certificate of Origin (DCO)

To accept a contribution we require a DCO sign-off on every commit. This
certifies that you wrote the code or otherwise have the right to submit it under
the project's license. The sign-off is the
[Developer Certificate of Origin 1.1](DCO) — add it with the `-s` flag:

```bash
git commit -s -m "feat: my change"
```

This appends a `Signed-off-by: Your Name <you@example.com>` line to the commit
message. The name and email must match your real identity. A DCO check runs on
every PR and will fail if any commit is missing the sign-off.

> A Contributor License Agreement (CLA) may be introduced later. If and when it
> is, contributors will be asked to sign it via a bot on their pull requests.
> For now, the DCO sign-off is the only contributor requirement — see
> [`CLA.md`](CLA.md) for the draft being held for future use.
