# AWS Marketplace billing

> **This page is about Flow bought through AWS Marketplace** — an installation
> running in your own AWS account, on your own cluster, invoiced by AWS. If you
> use Flow hosted by us, see [Plans & limits](/docs/plans-and-limits) instead. If
> your company runs Flow on its own servers outside Marketplace, nothing is
> metered at all and your operator sets the limits.

## What is different here

Everything runs in **your** AWS account. We never see your prompts, your
repositories or your data, and we never charge your card — AWS meters the
installation and puts it on your AWS bill, under the agreement you accepted when
you subscribed.

There is **no free allowance and no card** in this product. The trial and the
payment screens belong to the hosted product; here the subscription you already
have is the arrangement.

## What is metered

The same thing that is billed in the hosted product: **capacity, measured in
worker-minutes**.

A **worker** runs one session at a time. Each company in the installation has its
own number of workers, and the installation meters **the total across all of
them**, hour by hour, time-weighted. Half an hour at one worker and half an hour
at three is two worker-hours, not three.

One record is sent per hour, carrying:

- the **total** for the whole installation, which is what AWS charges for, and
- an **allocation per company**, so a bill can be read back to the organisations
  inside your installation.

### Whole minutes, rounded down

AWS accepts a whole number, so the quantity is **rounded down** and the
allocations are split so their parts still add up to that whole. The seconds
dropped this way are never charged for, and the exact figure is kept on our side
of the record for reconciliation.

## Every company must have a limit

In this product a company **cannot** be left without a session limit. Unlimited
has no encoding in a metering record — AWS takes a quantity or nothing — so an
unbounded company would run capacity that no record could describe.

Your administrator sets each company's limit on **Settings → General → Session
capacity**, and may raise or lower it at any time. The change takes effect
immediately, and the hour it happens in is billed for what was actually offered
during each part of it.

## When a bill looks wrong

The installation keeps its own hour-by-hour record of what every company was
offered, independent of what AWS received. If the two ever disagree, that record
is what settles it — ask your operator, or us.

A record AWS rejects is retried from that same ledger for up to six hours, which
is the window AWS still accepts a late record in. After that it is abandoned
rather than retried forever, and the hour is visible as unsent rather than
silently lost.

## Suspended companies

A suspended company runs nothing, so it is metered for nothing. Suspending is
therefore not a way to keep capacity and stop paying for it — the capacity goes
away with the ability to use it.

## See also

- [Session queues](/docs/session-queues) — why a session says **Queued**, and how
  a project reservation differs from a cap
- [Company workspace](/docs/company-workspace) — where a company's settings live
