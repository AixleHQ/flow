# Tasks & the Board

**Tasks** in the sidebar opens the project's board. This is where work enters
Flow and where results come back, so most people spend their day here.

## Columns

A board is ordered columns. Each column has a **purpose** — a sentence saying
what happens to a card while it sits there. That sentence is not decoration:
when a workflow runs from this column, the agent receives it as context.

A new project's board is empty and offers three templates:

| Template | Columns |
| --- | --- |
| **Simple Kanban** | Backlog · In Progress · Done |
| **Dev Team** | Backlog · Tech Design · Implementation · Code Review · QA · Ready for Release · Done |
| **Full SDLC** | The long form — design, tech design, development, QA, UAT, release, each with its own waiting column |

Pick one with **Use this template**, then add, rename, reorder, or remove
columns as the team's process changes. Columns collapse individually from the
header toggle or the column's ⋯ menu, and all at once with **Collapse all** —
a collapsed column still shows its cards as chips, coloured by their latest run.

## Cards

Create a card from a column's **+** button, or press **n** anywhere on the
board. A card carries a title, a description, a type, an assignee, tags, an
optional parent epic, subtasks, comments, and attachments.

Open a card and the detail drawer has tabs:

- **Details** — description, assignee, tags, the column it sits in (moving it
  from the **Column** select is the same as dragging it), and a *Latest run*
  tile.
- **Runs** — every workflow run this card has triggered, newest first. Click
  one to jump into the session.
- **Comments** — the conversation. Agents comment here too, so you can filter
  by author type to read only what people wrote, or only what agents produced.
- **Analytics** — what this single card has cost: run time, tokens, spend.

**Activity** (top of the board) opens a slide-over with everything that has
happened on the board recently — it stays open while you keep working.

## Finding things

- **Search** — press **/** to jump into it; it searches the whole board, not
  just loaded cards.
- **Type**, **Assignee**, **Tags** — filters that narrow the board; clicking a
  tag on a card filters by it, clicking again clears it.
- **Archived** — hidden by default, revealed with the toggle.
- **Presets** — saved views. Two are built in: **My Work** (only your cards)
  and **All Bugs**. Save your own filter combination as a preset and share it
  with the team, or keep it to yourself.

## Starting work from the board

Binding a column to a workflow is what turns a board into an assembly line.
Board settings (the toolbar's settings button, or a column's ⋯ menu) is where a
column gets its workflow and whether it fires **automatically** on entry or
waits for a person to press **Run workflow** on the card.

Once bound:

- Dropping a card into the column starts the run (auto), or offers the button
  (manual).
- A failed run offers **Retry run** from the card.
- The card's chips show the state of its latest runs and of any CI gate it is
  waiting on — see [Triggers & gates](/docs/starting-work).

> tip A column with no binding is still useful. Plenty of teams automate two
> columns out of seven and leave the rest as an ordinary Kanban board.
