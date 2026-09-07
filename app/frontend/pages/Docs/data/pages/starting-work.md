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
| **Slack message** | A message in a channel matches your text pattern | Optionally limited to one channel; a cooldown stops a busy channel from starting a run per message |
| **Incoming webhook** | An external system posts to the trigger's request URL | The workflow becomes a start API for anything that can send an HTTP request |

Triggers that create a card as they fire let you template its title and give
the run a subject, so the board does not fill up with rows called *Run 41*.

> tip Manual mode on a column trigger is the safest way to introduce
> automation: the process is bound and visible, but a person still decides when
> a card is ready for it.

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
