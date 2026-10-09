# Triggers & Gates

Two halves of one question: what starts a run, and what holds one up.

## Triggers

A trigger is attached to a workflow. Add one from the workflow's Triggers
panel, pick its kind, and fill in what that kind needs. Any trigger can be
switched off with **Enabled** without deleting it.

| Kind | Fires when | Worth knowing |
| --- | --- | --- |
| **Task enters column** | A card lands in the chosen column | The mode decides whether it runs on its own (**Auto**) or offers a button (**Manual**) |
| **On schedule** | A cron expression matches, in the timezone you pick | Use it for recurring work with no card behind it — a nightly report, a weekly sweep |
| **Chat message** | Someone addresses the Flow app in Slack or Microsoft Teams and the message matches your text pattern | Optionally limited to one channel or to direct messages; a cooldown stops a busy channel from starting a run per message. The thread gets a status card that follows the run |
| **Incoming webhook** | An external system posts to the trigger's request URL | The workflow becomes a start API for anything that can send an HTTP request |
| **Task tracker event** | An issue in a connected tracker is created, moves to a status, is assigned, or gets a comment | Offered once the project has a tracker attached; **Connect a board column** on the Trackers page sets one up for you |

Triggers that create a card as they fire let you template its title and give
the run a subject, so the board does not fill up with rows called *Run 41*.

A workflow can also start by hand — **Run** on a card or on the workflow — and
that needs no trigger at all.

> tip Manual mode on a column trigger is the safest way to introduce
> automation: the process is bound and visible, but a person still decides when
> a card is ready for it.

### Who a run belongs to

Every run belongs to a person and uses *their* agent credential. A card's run
belongs to its assignee when they have a connected agent, else to whoever moved
the card or pressed **Run** on it. A run from a schedule, a chat
message, a webhook or a tracker belongs to whoever created the trigger, because
nobody is at the keyboard when it fires — so the creator needs a connected
credential for every runtime the workflow uses.

## Gates

A **gate** is a check a card waits on before work moves on — usually CI. The
card shows a compact chip:

| Chip | Meaning |
| --- | --- |
| **waiting** | The check is still running. The chip pulses like a live run |
| **passed** | The check reported success |
| **failed** | The check reported failure — a verdict, so fix the code |
| **stale** | No verdict ever arrived. Something never reported; a tooltip explains why and offers to clear the gate |

**failed** and **stale** need different reactions, which is why they do not
share a colour. A failure means the work is wrong; a stale gate means you do
not know yet, and should look at why CI went quiet.

A collapsed column keeps this visible: a card that is gated shows as waiting
rather than as its running run, so a blocked card cannot hide behind a busy
one.
