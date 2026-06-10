# Agents

Agents are autonomous workers. Each receives a goal, plans the steps, and executes them without manual intervention.

## How agents work

When you define an agent, you give it a trigger and a goal. Aixle handles the rest.

| Component | Description |
|---|---|
| **Trigger** | What causes the agent to start — a git push, a schedule, or a manual call. |
| **Goal** | What the agent is trying to achieve, described in plain language or config. |
| **Tasks** | The steps the agent generates and executes to reach its goal. |
| **Report** | A summary of what the agent did, what succeeded, and what failed. |

> **info** **Agents are isolated.** Each runs in a sandboxed environment with only the access you've granted.

## Defining an agent

Agents are defined in `aixle.config.ts`. Each agent needs a name, a model, and a trigger.

```typescript
import { defineConfig } from 'aixle'

export default defineConfig({
  agents: {
    reviewer: {
      model: 'claude-sonnet',
      trigger: { on: 'pull_request', action: 'opened' },
      goal: 'Review the PR for bugs, security issues, and style violations',
      tools: ['read_file', 'search_code', 'post_comment'],
    },
    tester: {
      model: 'gpt-4o',
      trigger: { on: 'push', branch: 'main' },
      goal: 'Run the test suite and fix any failures',
      tools: ['read_file', 'write_file', 'run_tests', 'git_commit'],
    },
  }
})
```

## Agent tools

Tools are the actions an agent can take. You grant tools explicitly — agents cannot use tools you have not listed.

| Tool | What it does |
|---|---|
| `read_file` | Read any file in the repository |
| `write_file` | Create or overwrite a file |
| `run_tests` | Execute the project's test command |
| `search_code` | Semantic search across the codebase |
| `git_commit` | Stage and commit changes |
| `post_comment` | Post a comment on a PR or issue |
| `bash` | Run arbitrary shell commands |

> **danger** **`bash` is powerful.** Only grant it to agents with a tightly scoped system prompt. An agent with unrestricted `bash` access can modify any file in the repo.

## Models

Aixle routes tasks to the model you specify. Supported models:

```yaml
models:
  - claude-opus-4-5
  - claude-sonnet-4-5
  - gpt-4o
  - gpt-4o-mini
  - gemini-1.5-pro
  - gemini-1.5-flash
```

You can route different agents to different models based on cost, latency, or capability requirements.

## Monitoring

Every agent run produces a full session log — every file read, command executed, and decision made. Logs are accessible in the web UI under **Project → Sessions**.

<details>
<summary>Replay and audit sessions</summary>
<div>

Session replays let you step through every action the agent took. You can see the exact prompt sent to the model, the tool calls made, and the output returned at each step. This makes it straightforward to diagnose unexpected behaviour.

</div>
</details>
