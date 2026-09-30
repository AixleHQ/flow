# Plans & limits

> **This page is about Aixle Flow hosted by us.** If your company runs Flow on its
> own servers, nothing here applies — your operator sets the limits and nobody is
> billed. If you bought Flow through AWS Marketplace, see
> [AWS Marketplace billing](/docs/aws-marketplace-billing) instead: AWS invoices
> you, and there is no free allowance or card here.

## What you pay for

Capacity, and nothing else. No seats, no charge per token, no charge per run.

A **queue** is one session at a time. A workspace with four queues runs four
sessions side by side; a fifth waits. Queues are what you buy, and what you set on
**Settings → General → Session capacity**.

A queue is a reserved slot: it is charged for every hour it stands ready, whether
or not a session is running in it. That is deliberate — the capacity is yours
whenever you want it, not only when you happen to use it.

| | |
| --- | --- |
| One queue-hour | **$5.00** |
| One queue, kept open for a month | 720 hours — **$3,600** |

Usage is measured **hourly and time-weighted**: half an hour at one queue and half
an hour at three is two queue-hours, not three. Raising or lowering your limit
takes effect immediately, not next month.

Your invoice is charged in **whole queue-hours**. A part hour left over at the end
of a billing period is rounded down and not charged for — we never round a
fraction up into a chargeable hour.

## Your first 100 queue-hours are free

Every new workspace starts with **100 free queue-hours**, and nothing is charged
for them.

**They are a quantity, not a trial period, and you set the rate they are spent
at.** Running ten sessions at once uses ten queue-hours an hour; running one uses
one. The same hundred hours last about four days at one queue and about ten hours
at ten.

Your limit is yours throughout — nothing is capped while the free capacity lasts,
so you are trying the product you would actually be buying. A bigger limit buys a
shorter trial, not a bigger allowance.

A banner at the top of every page shows what you have spent and roughly how long
what is left will last **at the rate you are currently running**.

## When the free capacity runs out

- **No new session starts.** Sessions already running **finish** — nothing is
  stopped part-way.
- Queued work stays queued, and starts as soon as the workspace is running again.
- You are not charged for the time you are stopped.

To carry on, talk to us and we will switch your workspace to a paid plan. A card
can be added from the product itself once payment is live.

## Who can change what

| | |
| --- | --- |
| The session limit | Any **administrator** of the workspace, on Settings → General |
| Reserving part of it for one project | Any administrator, on that project's settings |
| Removing the limit entirely | Nobody — a workspace without a limit is one nobody is invoiced for. Ask us |

Raising your limit costs more per hour from the moment you raise it. Lowering it
costs less from the moment you lower it. Nothing is prorated at the end of a
month, because nothing was bought for a month in the first place.

## Where the numbers come from

Your capacity is recorded hour by hour, per workspace, exactly to the second — the
same record the free allowance is counted from and the same one an invoice is
built from. If a figure ever looks wrong, ask us: we can show you the hours.

## See also

- [Session queues](/docs/session-queues) — why a session says **Queued**, and how
  a project reservation differs from a cap
- [Team & access](/docs/people-and-access) — who gets into the workspace, and what
  verifying your domain changes
