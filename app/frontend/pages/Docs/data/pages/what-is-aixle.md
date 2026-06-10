Aixle lets anyone run developer tasks using AI agents — without touching a terminal. Describe what you want, and agents handle the rest.

## Key concepts

A small set of primitives gives you a complete mental model of how the system works.

## How it works

You describe a goal in plain language. Aixle breaks it into tasks, assigns them to agents, and executes them — reporting back at each step.

### For non-developers

Use the web UI to describe what you want in plain English. Aixle handles the rest — no terminal, no config files.

> **info** **No code required.** Describe the task, agents run it. Developers can also use the CLI or API for full control.

### For developers

Use the CLI or API for full programmatic control. Define agents in config, trigger them on git events, and integrate with your existing workflow.

> **warning** **Breaking change in v0.4.** The `agent.run()` method signature has changed. See the migration guide for details.

> **danger** **Never commit API keys.** Use environment variables or the Aixle secrets manager to store credentials.

> **tip** **Pro tip.** Use `aixle run --dry-run` to preview what an agent would do without executing anything.

## Configuration

Aixle is configured via a single `aixle.config.ts` file in your project root.

<details>
<summary>Advanced configuration options</summary>
<div>

Advanced options include custom agent timeouts, retry strategies, environment isolation levels, and notification webhooks. These are covered in the full config reference.

</div>
</details>

```typescript
import { defineConfig } from 'aixle'

export default defineConfig({
  project: 'my-app',
  agents: {
    deploy: { trigger: 'on-merge', target: 'production' }
  }
})
```

## How Aixle compares

| Feature | Aixle | GitHub Actions | Jenkins |
|---|---|---|---|
| Natural language input | ✓ | ✗ | ✗ |
| AI agent execution | ✓ | ✗ | ✗ |
| No-code UI | ✓ | Partial | ✗ |
| Self-hostable | ✓ | ✗ | ✓ |
| Open source | ✓ | ✗ | ✓ |
