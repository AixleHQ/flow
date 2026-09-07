# AI Builder

Describe a process in plain language and let Flow build it: board columns,
workflows, steps, and the tools they need. The sidebar entry is **AI Builder**
with a **Build with AI** button; inside, the feature calls itself **Aixle
Builder**.

## Before you start

The builder runs on a real agent, so the project needs at least one configured
runtime — it says so plainly if none is connected. Viewers do not get the start
control, since they cannot execute work in the project.

## A builder session

1. **Say what you want.** "When a card lands in Triage, summarise it, label it,
   and draft a reply for review." Pick the model, and attach project assets if
   the builder should read something first.
2. **Watch it work.** The session shows its terminal live and an activity feed
   naming each thing it creates as it creates it.
3. **Check what it made.** The **Workflows** and **Board** tabs show the result
   — workflows with their steps, columns with their auto-trigger bindings —
   while the session is still open.
4. **Finish Session** when it looks right.

Previous builder sessions stay in a list; an unfinished one offers to continue
where it stopped. A session that ended badly keeps its error, so you can see
what it failed on rather than guessing.

## Afterwards

Everything the builder made is ordinary: the workflows open in the
[workflow editor](/docs/running-workflows), the columns behave like any other
[board](/docs/tasks) columns. Adjust by hand — the builder is a starting point,
not a black box you have to accept whole.

> tip The builder is at its best on a process you can describe in a paragraph.
> For a seven-stage release pipeline, build the first two stages with it and
> extend by hand.
