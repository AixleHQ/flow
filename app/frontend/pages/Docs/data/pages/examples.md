# Worked Examples

Two end-to-end stories. Each names every screen it touches, so you can replay
it in your own workspace.

## Drop a card, get a pull request back

**The setup.** A lead connects the GitHub integration and links the service's
repository ([Repositories & Integrations](/docs/repositories)). The board uses
the **Dev Team** template, and its *Implementation* column is bound to an
implementation workflow in board settings, set to **Auto**.

**The work.** They write a card describing a small feature and drag it into
*Implementation*.

1. The run starts on its own. In [Sessions & Runs](/docs/sessions-and-runs) it
   shows four steps: one plans, two run in parallel — implementation and tests
   — and a final step waits for a person.
2. The lead watches the implementing step's terminal live on the run page.
3. The agent posts a summary of the diff to the card as a comment; the card's
   CI gate goes to **waiting** while the pipeline runs, then **passed**.
4. The waiting step shows **Approve & continue**. The lead approves, and the
   final step opens the pull request in the team's own repo.
5. The card moves to *Code Review*. Its Analytics tab shows what the whole
   thing cost.

**What made it work.** The column's purpose told the agent what
*Implementation* means here; the persona told it how the team reviews; the
repository resource is what let it push at all.

## Build a workflow from one prompt

**The setup.** An operator has a support inbox landing on the board and no
process for it yet.

1. They open [AI Builder](/docs/ai-builder) and type: *"When a card lands in
   Triage, summarise it, label it, and draft a reply for review."*
2. The builder proposes a *Triage* column with an auto binding, a three-step
   workflow, and the connector it needs to read the ticketing system. The
   Workflows and Board tabs show all of it before anything is final.
3. The operator finishes the session, adds the connector's credential in
   [Secrets & Variables](/docs/secrets), and drops a test card into *Triage*.
4. The run appears in Sessions & Runs; the draft reply lands on the card as a
   comment.
5. They edit the second step by hand — the label set was too broad — and leave
   the rest as generated.

**What made it work.** The builder produced ordinary objects. Nothing about the
workflow it wrote is special: it is edited, run, and measured like anything
built by hand.
