# Quick start

Get Aixle running in under 5 minutes. Install the CLI, connect your repo, and run your first agent task.

## Install

Install the Aixle CLI globally using npm or your package manager of choice.

```bash
npm install -g aixle
aixle login
```

## Connect your repo

Run `aixle init` in your project root. Aixle will detect your stack and scaffold a config file.

```bash
cd my-project
aixle init
```

> **info** **Node 18+ required.** Run `node -v` to check your version before installing.

## Run your first task

Once connected, describe a task in plain English from the CLI or the web UI.

```bash
aixle run "Add input validation to the registration form email field"
```

Aixle will:

1. Analyse your codebase to understand the relevant files
2. Generate the code change
3. Run your test suite to verify the result
4. Open a pull request with a full summary

> **tip** **Use `--dry-run` first.** Run `aixle run --dry-run "..."` to preview what the agent would do before any files are changed.

## Connect GitHub

To let Aixle open pull requests automatically, install the GitHub App and grant it access to your repositories.

```bash
aixle github connect
```

Follow the browser prompt to authorize the app. Once connected, Aixle can read code, write branches, and open PRs on your behalf.

> **warning** **Permissions scope.** Aixle requests the minimum GitHub permissions needed — read code, write pull requests, read issues. It does not request write access to repository settings or webhooks.
