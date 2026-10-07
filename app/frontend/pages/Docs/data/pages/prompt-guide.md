# Prompt guide: writing instructions an agent can run

A session's **instructions** are the prompt the agent receives. This page is about writing them well in Aixle Flow: what the agent actually sees, where its files are, what belongs in the instructions and what belongs on the step form, and the habits that keep a workflow running without a person watching it.

It is not general prompt-engineering advice. Everything here is specific to one Flow session: one container, one agent, and the resources you attached to it.

> **One thing first.** Flow sends your instructions to the agent **exactly as you wrote them**. Nothing in the text is substituted at run time. A `{{something}}` you type stays `{{something}}` in the prompt, and the agent sees the braces. To point the agent at a file, write the file's **path** (see [Where things are](#where-things-are-in-the-container)). `@` references to assets, sessions and connections are planned, and this page will describe them when they ship.

---

## What the agent sees

Your instructions are not the whole prompt. Before a session starts, Flow writes a context file for the agent, a set of sections in a fixed order. Knowing what is in it tells you what you don't need to repeat, and what you do.

| Section | What it holds | What it means for you |
|---|---|---|
| **Rules** | In auto-run: never ask questions, save results to `/workspace/outputs/`, finish with `finish_session` or `fail_session`. Plus the language rule. | You don't need to restate these. Don't contradict them either: "ask me if unsure" can't work in auto-run. |
| **Your role** | The agent's persona: title, persona, communication style, principles. | Put *who the agent is* here once, on the agent. Put *what this step does* in the instructions. |
| **Workflow and step** | Workflow name and description, "Step N of M", the Slack message that triggered the run (if any), then **your instructions**, verbatim. | The instructions sit under the step heading. Write them as the task for this step, not the whole workflow. |
| **Sub-steps checklist** | Each sub-step's name, id, state and instructions, and a note to mark them with `mark_sub_step`. | A good way to make a long step checkable. See [Sub-steps](#sub-steps). |
| **Previous steps** | For steps that already finished: their **note** (up to 500 characters) and their sub-step notes. **Not their files.** | If a later step needs what an earlier step produced, make the earlier step write a file and set **Run after**. See [Passing work between sessions](#passing-work-between-sessions). |
| **Board** (board-triggered runs) | The card's title, id, column, priority, tags, assignee, **description (first 500 characters)**, the **last 5 comments (first 200 characters each)**, all columns, and the board tools. | The agent sees only the start of a long description, and only a glimpse of the thread. If the full thread matters, tell it to read the comments with `board_get_comments`. |
| **Tools and resources** | Shell and MCP tools (always including `aixle-tools`), attached tools, repositories, input assets **with their paths**, skills. | Attached resources are listed for the agent, but nothing tells it *which one to use for this step*. The instructions do. |
| **Config items** | Names, types and descriptions of secrets and variables. **Never their values.** | Tell the agent which item to read, by name, with `get_config_item`. Never paste a secret into instructions. |

The whole context has a budget of roughly 6,000 tokens. Over that, previous steps, board comments, tools, skills and repositories are compressed first. Your instructions and the rules are kept.

---

## Where things are in the container

| Path | What's there | How it gets there |
|---|---|---|
| `/workspace/assets/<folder>/<name>` | Files you attached: workflow base assets, the step's assets, the run's input assets | Attach them on the workflow (Base Resources) or on the step |
| `/workspace/assets/<name>` | **Files produced by the steps listed in this step's Run after** | Automatic, when the earlier step wrote them to `/workspace/outputs/` |
| `/workspace/outputs/` | Whatever the agent writes here is **collected after the session** as a run asset, named by its relative path | The agent writes here. Nothing else is kept. |
| `/workspace/repo/` | Clones of the attached repositories | Attach repositories on the workflow or the step |
| `/workspace/_bmad/` | The BMAD method files | Turn on BMAD for the step |

Two things that catch people out:

- **Files attached to a board card are not mounted.** The agent fetches them with `board_get_task_assets`. Say so in the instructions if the step depends on them.
- **Anything written outside `/workspace/outputs/` is gone** when the container stops.

---

## The shape of instructions that run

Instructions an agent can finish on its own tend to have the same six parts. Not every step needs all six, but a step that fails usually lacks one of them.

1. **Task.** One or two sentences: what this step is for.
2. **Done when.** The concrete thing that counts as finished: a file with a given name, a comment on the card, a card in a given column. An agent that doesn't know when it's done either stops early or never stops.
3. **Inputs.** What to read, **by path**, and what to do if it isn't there.
4. **Steps.** The work, in order, as numbered items when order matters.
5. **Rules.** What the agent must not do: invent ids, skip a required tool, guess a value it can't read, move the card to a column other than the ones named.
6. **Output and exit.** What to write where (`/workspace/outputs/<name>`), what to post, where to move the card, and what to do on each outcome: success, blocked, failed.

**Bad**

```
Review the PR and update the board.
```

Which PR? Update it how? When is it done? What if CI is red?

**Good**

```
## Task
Review the pull request linked in the card description against the card's acceptance criteria.

## Done when
A comment tagged `review_findings` is on the card, and the card is in Implementation (blocking
findings) or Merge and deploy (clean).

## Inputs
- The card: read the full description and all comments with `board_get_task` and `board_get_comments`
  (the context shows only the first 500 characters).
- The repository at `/workspace/repo/`.
- If the card has no PR link, stop: post a `blocked` comment saying so, move the card to Blocked,
  and finish.

## Rules
- Review statically. Do not run the test suite.
- A finding is "blocking" only if it breaks an acceptance criterion or the build. Everything else is
  a note.

## Output and exit
- Post one comment starting with **BLOCKING (n)** or **CLEAN**, listing findings with file:line.
- Blocking → move to Implementation. Clean → move to Merge and deploy. Then call `finish_session`.
```

---

## Instructions vs the step form

A lot of what people try to say in instructions is really a setting. When it's a setting, set it. The instructions can't change it, and saying it in prose does nothing.

| You want… | Where it goes |
|---|---|
| A specific persona | **Agent** on the step. Its persona becomes "Your role". |
| A specific CLI or model | **Execution environment** and **Model** on the step |
| The agent to be *able* to use a tool, skill or MCP server | Attach it on the step or on Base Resources |
| The agent to *use* that tool, skill or server in this step | **Name it in the instructions** ("create the issue with the Linear MCP"). Attaching alone doesn't tell the agent it's wanted here. |
| The agent to read a secret or variable | Attach the **config item**, and name it in the instructions ("read `STAGING_URL` with `get_config_item`") |
| The agent to read a file | Attach the **asset**, and give its path in the instructions |
| A step to wait for another | **Run after** on the step. It also puts the earlier step's output files in `/workspace/assets/`. |
| A step to fail if a file it needs is missing | A required **input spec** with that file's name. It is checked before the step starts. |
| A step to fail if it didn't produce a file | A required **output spec** with that name (or a name pattern). It is checked when the step ends. |
| A step to be skipped when its output already exists | **Skip policy: if outputs exist** (it needs output specs). `manual` currently has no effect at run time. |
| A retry on failure | **On failure: retry**. The number of retries isn't in the builder yet and defaults to 0, so retry currently behaves like fail. |
| A step to run without a person in the loop | **Auto-run available**, on a run mode that allows it |

The mismatch to avoid is in both directions. Don't attach every server on the project and write a prompt that never says which to use. And don't name a server in the prompt that isn't attached: the agent will look for it and fail, or improvise.

---

## Referencing things in instructions (today)

Until `@` references ship:

- **Files:** write the path. `/workspace/assets/brand/voice.md`, `/workspace/assets/summary.md` (an earlier step's output), `/workspace/outputs/report.md`.
- **Tools, MCP servers, skills:** use the name as it appears in the step's resources ("the GitHub MCP", "the `chat_post_message` tool").
- **Config items:** use the item's name exactly, and tell the agent to read it with `get_config_item`.
- **Board objects:** the agent's board tools take ids. If the step works on "the card that triggered this run", say that. The agent has it in its context.
- **`{{artifact_name}}`**, from the builder's helper text, **is not replaced by anything**. Don't use it. Write the path instead.
- **`{{inputs.<key>}}`** is different, and real, but only in **templates**. It is filled in once, when the template is installed, and a missing input becomes empty text. It is never resolved during a run.

---

## Passing work between sessions

Sessions don't share a container, and a later session doesn't see an earlier one's files unless you wire them.

1. In the earlier session, tell the agent to write the result to `/workspace/outputs/<name>`, and add a required **output spec** for `<name>`.
2. In the later session, set **Run after** to the earlier one. Flow puts `<name>` at `/workspace/assets/<name>`. Add a required **input spec** for `<name>` so the step fails clearly if it's missing, rather than improvising.
3. In the later session's instructions, read `/workspace/assets/<name>`.

The earlier step's **note** (its `finish_session` summary) also reaches later steps, but only the first 500 characters. Use it for "what happened", not for the work itself.

---

## Sub-steps

Sub-steps appear to the agent as a **checklist** under the step, with ids, and the agent ticks them off with `mark_sub_step`. They are the best tool you have for making a long step reliable. The agent has to account for each item, and a reviewer can see which one it stopped on.

- Use one sub-step per thing the agent must not skip.
- **The "required" flag is not enforced at run time.** The agent isn't stopped if it skips a required sub-step. If it must not finish without one, say so in the instructions: "Do not call `finish_session` until every sub-step is marked done or explicitly marked not applicable with a reason."
- **When you add a rule to the instructions, add a matching sub-step.** A rule buried in a long prompt is the first thing a busy agent misses. A checklist line is not.

---

## Habits that save runs

These come from running a large board of agent workflows day to day. Each one is a failure we saw more than once.

**Tell the agent where its input is, and what an empty input means.** "Files attached to the triggering Slack message are already in your workspace. A message that is only a mention and a word, while files are there, is not an empty request." Without this, agents reply "nothing attached" while the files are sitting in their workspace.

**Define the one word the decision turns on.** If a step routes on "blocked", say what a blocker is and what is *not* one. An agent will otherwise hold work on anything described as "still open".

**The agent trusts the text it's given, not the history behind it.** A card whose description still says "blocked on a product decision" stays blocked in the agent's eyes, even after the answer is in the comments. Keep descriptions current, or tell the agent to read the latest decision comment first.

**Exactly one step moves the card.** In a workflow with several steps, name the one that moves the card and forbid the others. Have earlier steps end with an explicit routing line ("routing: implementation"), so the mover doesn't guess.

**Every outcome gets an exit.** Success, blocked and failed each need an action: a comment, a column, a Slack line, `finish_session` or `fail_session`. A step that only describes the happy path ends in the middle of the unhappy one.

**Fail loudly.** "If you can't read X, stop and say so" beats "try your best". A silent guess looks exactly like success until much later.

**Don't let the agent trust a success it didn't check.** Some calls return success without doing what was asked. Tell the agent to read the result back ("re-read the card and confirm its column"), not to trust the response.

**Keep what matters in the first lines.** Card descriptions are cut at 500 characters in the context. Put the decision, the acceptance criteria or the link first.

**Keep a copy before you edit a long step.** Save the old text somewhere before replacing it, so a bad edit can be undone in one paste.

---

## Worked examples

### 1. One session: read a file, write a file, use an attached server

*Step form:* asset `sales-notes.csv` attached (folder `inputs`) · Linear MCP attached · output spec `summary.md` (required) · Auto-run available.

```
## Task
Summarise this week's sales notes and open one Linear issue per blocker found.

## Done when
`/workspace/outputs/summary.md` exists, and every blocker in it has a Linear issue linked next to it.

## Inputs
- `/workspace/assets/inputs/sales-notes.csv`. If the file is missing or empty, call `fail_session`
  with "sales-notes.csv missing or empty" and stop.

## Steps
1. Read the CSV. Group rows by account.
2. Write `/workspace/outputs/summary.md`: one section per account, three bullets at most, then a
   "Blockers" list.
3. For each blocker, create an issue with the Linear MCP in the team named in the row's `team`
   column. Add the issue link next to the blocker in the summary.

## Rules
- Do not invent a team. If a row has no team, list the blocker under "Needs a team" without an issue.

## Exit
Call `finish_session` with a one-line note: accounts covered, issues created.
```

### 2. Two sessions: one produces, the next consumes

*Session 1, "Draft":* output spec `draft.md` (required).
*Session 2, "Edit":* Run after **Draft** · input spec `draft.md` (required) · output spec `final.md` (required).

Session 1:

```
Write the release note for the changes listed in the card description. Save it to
`/workspace/outputs/draft.md`. Finish with a note naming the three biggest changes.
```

Session 2:

```
## Task
Edit the release note drafted in the previous session.

## Inputs
- `/workspace/assets/draft.md`: the previous session's output, placed here because this session
  runs after it.
- The "Previous steps" section of your context has the draft session's note. Use it to check nothing
  big was left out.

## Done when
`/workspace/outputs/final.md` exists, under 300 words, in plain language, with the three biggest
changes first.
```

Session 2 gets session 1's **file** (through Run after) and its **note** (through the context), not its transcript.

### 3. A board-triggered step that routes a card

```
## Task
Decide whether the card that triggered this run is ready for Tech Design.

## Inputs
- The card: read the full description and all comments with `board_get_task` / `board_get_comments`.
  The context shows only the start.

## Ready means
Acceptance criteria present (Given / When / Then), no open question addressed to the client, and a
named owner for anything still pending.

## Exit, exactly one of
- Ready → comment `ready: <one line why>`, move the card to Tech Design.
- Not ready → comment `not ready:` with the missing items as a list, move the card to Needs Planning.
Then re-read the card, confirm its column, and call `finish_session`.
```

---

## Things that don't work

- **`{{summary.md}}`, `{{artifact_name}}` or any other braces.** They are not substituted. Write the path.
- **`@GitHub` or `@someone` typed as text.** It isn't a mention and doesn't bind to anything.
- **Raw ids pasted from another page**, such as a step id or asset id, "so the agent can find it". The agent can't resolve them. Give paths and names.
- **Naming a server, tool or config item that isn't attached.** The agent can't reach it.
- **"Ask me if anything is unclear"** in an auto-run step. The rules forbid questions. Tell it what to do instead.
- **Instructions that contradict the form**, such as "skip this if the report exists" while the skip policy is `never`, or "retry three times" while retries are 0. The form wins.
- **Relying on a required sub-step to stop the agent.** It won't. Say it in the instructions.

---

## When a run goes wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| "Input validation failed: Required input missing: X" before the step starts | An input spec names a file that no Run-after step produced and no attached asset provides | Check the spelling against the earlier step's output spec, or attach the asset |
| "Output validation failed" after the step | The agent didn't write a required output, or wrote it under another name | Put the exact path in "Done when" and in the steps |
| The agent says a file isn't there | It looked outside `/workspace/assets/`, or the file is a card attachment (not mounted) | Give the full path. For card files, tell it to use `board_get_task_assets`. |
| A later step "doesn't know" what an earlier one did | Only the earlier step's note (500 characters) is shared. Its files need Run after. | Write the result to a file, and set Run after plus an input spec. |
| The agent acts on an outdated decision | It read the card description (cut at 500 characters), not the latest comment | Put the current decision at the top of the description, or tell it to read comments first |
| The step "finished" but skipped a required checklist item | Required sub-steps aren't enforced | Add "don't finish until every sub-step is marked" to the instructions |
| The agent uses the wrong server or tool | Several are attached and the prompt doesn't say which | Name the one to use for this step |
