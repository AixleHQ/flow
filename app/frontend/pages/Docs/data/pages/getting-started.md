# Getting Started

From an invitation to your first running workflow.

## Sign in

Accept the invitation you were emailed, or sign in if an account already exists
for you. Flow takes a password, an emailed sign-in link, a passkey, Google,
Microsoft, or your company's own single sign-on — whichever your installation
and your workspace allow. See [Signing in & SSO](/docs/signing-in).

## Onboarding

First-run onboarding is two steps and takes a minute.

**1. About you.** Pick the role card that matches how you will work, and choose
the language you want agents to write in — task summaries, review notes, and
generated documents follow it. Continue stays disabled until both are set.

**2. Connect agents.** One card per supported runtime: Claude Code, Cursor
CLI, Codex, Gemini CLI, Antigravity CLI, Grok, Kiro CLI and GitHub Copilot CLI. Click **Connect**
on the one whose
account you already have. A terminal opens inline, the runtime's own login runs
in it, and Flow keeps the resulting credential for you.

Nothing can run on your behalf until you connect at least one agent.

> info Want to look around first? Choose **Skip for now** and confirm. You can
> browse projects and boards — and, as an admin, invite members and manage the
> company — right away. Workflows, sessions and the Builder stay blocked with
> "No agent credentials" until you connect an agent in **Profile**.

> info Invited as a **viewer**? The connect step is replaced by a short tour.
> Viewers read boards, runs and results; they do not start work, so they do not
> need a credential.

## Getting started and the product tour

Where your installation has the product tour switched on, onboarding ends on a
**Getting started** page instead of the project list. Its cards connect an
agent, open the template catalog, start AI Builder or set up Personal MCP, and
start the **product tour**: about five minutes that install the *Hello Flow*
starter template into a new project and run its workflow with your agent, from
the board to the finished result. A viewer gets a shorter tour of projects,
the board and Sessions & Runs, with nothing to run.

You land on Getting started after each sign-in until you finish or skip your
tour. Start it again at any time from **Start product tour** in the user menu.

## Your profile

Everything personal lives in **Profile**, on five tabs.

| Tab | What is there |
| --- | --- |
| **Account** | Your display name, your connected agent credentials, default models, the companies you belong to, and the [teams](/docs/project-teams) you are in — with **Leave**, and a switch that keeps you out of teams altogether |
| **Usage** | Your own sessions, tokens and spend — plus any usage window that applies to you, with the time left on it |
| **MCP** | Personal access: generate a token so an agent you run *outside* Flow (your own Claude Code, for example) can reach your Aixle projects |
| **Security** | Your sign-in methods, passkeys, authentication codes, and the devices you are signed in on |
| **Connected accounts** | Your own GitHub, GitLab and Bitbucket accounts, so agents can push and open pull requests as you — with a per-project switch for your tasks and for other people's |

Credentials expire the way the underlying product's do. Reconnect from the same
place — the Account tab — and runs pick the new credential up.

## Open your first project

Go to **Projects**, pick one, and you land on its **Overview**: recent
activity, how tasks are spread across the board, runs, sessions, success rate,
and spend. From there, **Tasks** is the board where work actually happens.

## What to read next

1. [Tasks & the board](/docs/tasks) — where work enters and results land
2. [Building workflows](/docs/running-workflows) — turning a process into sessions and steps
3. [Sessions & Runs](/docs/sessions-and-runs) — watching and steering a run
