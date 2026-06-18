# Contributing to Aixle App

Thank you for your interest in contributing to Aixle App!

## Getting Started

1. Create a new branch from `develop` for your feature or fix.
2. Make your changes following the project conventions.
3. Run the full check suite before submitting (this is what CI runs):

```bash
make check_all
```

## Code Quality

Before opening a PR, run `make check_all` — it runs all of the below in
parallel and fails if any one fails. The individual targets:

| Command | Description |
|---------|-------------|
| `make check_all` | Run all checks in parallel (rails-test, rubocop, brakeman, eslint, typescript) |
| `make lint` | Run all linters |
| `make test` | Run all tests |
| `make rubocop` | Ruby linter |
| `make eslint` | JavaScript/TypeScript linter |
| `make brakeman` | Security analysis |
| `make typescript` | TypeScript compile check |

Auto-fix options are available via `make rubocop-fix` and `make eslint-fix`.

## Pull Request Guidelines

- Keep PRs focused on a single concern.
- Write descriptive commit messages.
- Ensure CI passes before requesting review.
- Reference related issues in the PR description when applicable.
