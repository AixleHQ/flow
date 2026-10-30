# Plans & limits

> **This page is about Aixle Flow hosted by us.** If your company runs Flow on its
> own servers, nothing here applies — your operator sets the limits and nobody is
> billed. If you bought Flow through AWS Marketplace, see
> [AWS Marketplace billing](/docs/aws-marketplace-billing) instead: AWS invoices
> you, and there is no free trial or card here.

## What you pay for

Capacity, and nothing else. No seats, no charge per token, no charge per run.

A **worker** runs one session at a time. A workspace with four workers runs four
sessions side by side; a fifth waits. Workers are what you buy, and what you set on
**Settings → General → Workers**.

A worker is reserved capacity: it is charged for every hour it stands ready,
whether or not a session is running on it. That is deliberate — the capacity is
yours whenever you want it, not only when you happen to use it.

| | |
| --- | --- |
| One worker-hour | **$5.00** |
| One worker, kept for a month | 720 hours — **$3,600** |

Usage is measured **hourly and time-weighted**: half an hour at one worker and half
an hour at three is two worker-hours, not three. Raising or lowering your limit
takes effect immediately, not next month.

Your invoice is charged in **whole worker-hours**. A part hour left over at the end
of a billing period is rounded down and not charged for — we never round a
fraction up into a chargeable hour.

## Your first 30 days are free

Every new workspace starts with a **30-day free trial**, and nothing is charged
for it.

**The trial runs one worker**: one session at a time, the rest wait their turn.
Anyone in the workspace who can make changes can add a card from the banner.
Once one is added, an administrator chooses how many workers to keep on
**Settings → General → Workers**.

A banner at the top of every page shows how many days are left and the trial's
last day.

## When the trial ends

- **No new session starts.** Sessions already running **finish** — nothing is
  stopped part-way.
- Queued work stays queued, and starts as soon as the workspace is running again.
- You are not charged for the time you are stopped.

To carry on, anyone in the workspace who can make changes adds a card from the
banner; an administrator can also do it from **Settings → Billing**. The workspace runs again as soon as the card is confirmed.

## Your bill so far

**Settings → Billing** shows administrators where the subscription stands, the
current billing period, and the worker-minutes used in it so far, with an estimate
of what they cost. The estimate is counted the way the invoice is, but it is an
estimate: each hour is added once it closes, and the invoice has the final amount.

## Cancelling

An administrator cancels from **Settings → Billing**, in two steps: the button,
then a confirmation that says what will happen.

- The subscription ends **at once**. Workers are billed for every hour they are
  available, so it does not run on to the end of the billing period.
- No new session starts, as when the trial ends. Sessions already
  running finish.
- Usage up to the minute of cancelling is billed on a **final invoice**, issued
  and charged a few minutes later. Settings → Billing links to it once it is
  ready.
- Your projects, workflows and history are **kept**, and administrators can still
  sign in. Adding a card restores access.

Every administrator gets an email when the subscription is cancelled.

## If a payment fails

The workspace stops at once, as above: no new session starts and running ones
finish. The banner and **Settings → Billing** offer **Pay invoice**, which opens
the unpaid invoice. Once it is paid, the workspace runs again, and the card you
paid with is the one charged from then on.

If the card is declined for the **final invoice** of a cancelled subscription,
every administrator gets an email, and Settings → Billing offers **Pay final
invoice**. A new card can be added once it is paid.

## Who can change what

| | |
| --- | --- |
| The number of workers | Any **administrator** of the workspace, on Settings → General |
| Reserving some of them for one project | Any administrator, on that project's settings |
| Removing the limit entirely | Nobody — a workspace without a limit is one nobody is invoiced for. Ask us |
| Adding a card, cancelling, paying an unpaid invoice | Any administrator, on Settings → Billing |

Raising your limit costs more per hour from the moment you raise it. Lowering it
costs less from the moment you lower it. Nothing is prorated at the end of a
month, because nothing was bought for a month in the first place.

## Where the numbers come from

Your capacity is recorded hour by hour, per workspace, exactly to the second — the
same record the free trial is counted from and the same one an invoice is
built from. If a figure ever looks wrong, ask us: we can show you the hours.

## See also

- [Session queues](/docs/session-queues) — why a session says **Queued**, and how
  a project reservation differs from a cap
- [Team & access](/docs/people-and-access) — who gets into the workspace, and what
  verifying your domain changes
