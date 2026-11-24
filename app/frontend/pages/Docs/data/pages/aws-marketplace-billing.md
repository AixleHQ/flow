# AWS Marketplace billing

> **This page is about Flow bought through AWS Marketplace**, which sells it two
> ways: **hosted by us** and billed to your AWS account, or as an **installation
> in your own AWS account**, on your own cluster. AWS invoices you for either.
> If you pay us by card, see [Plans & limits](/docs/plans-and-limits) instead. If
> your company runs Flow on its own servers outside Marketplace, nothing is
> metered at all and your operator sets the limits.

## Hosted by us, billed through AWS

The workspace works as one paid for by card — workers, queues and **Settings →
General → Workers** are as [Plans & limits](/docs/plans-and-limits) describes —
but AWS bills it, at the price per worker-minute in your AWS agreement. There is
**no free trial and no card**.

### Subscribing

Subscribe to the listing in AWS Marketplace and choose **Set up your account**.
AWS sends you to Flow, which signs out whoever was signed in there and asks for
your work email.

- **No workspace has your email's domain yet**: you set one up. AWS bills it
  from the first minute. It starts on one worker, and an administrator can raise
  that on **Settings → General → Workers** straight away. If AWS has not
  confirmed the agreement yet, the workspace waits until it does, usually a few
  minutes.
- **Your domain already has a workspace**: a second one cannot be made. Ask its
  administrators to apply your subscription instead. Flow emails a link to the
  address you give; open it and choose **Confirm the request** to send it.

A workspace on its free trial or paying by card can switch with **Pay via AWS
Marketplace** on **Settings → Billing**, where the listing is configured. The
subscription then reaches the workspace as such a request.

### Applying a subscription to an existing workspace

The request appears on **Settings → Billing**, where an administrator applies or
declines it. It cannot be applied until AWS has confirmed the subscription.
Applying takes effect at once:

- The workspace is billed through the AWS account named in the request, which
  you may not control. Whoever holds that subscription can end it, and the
  workspace stops when they do.
- A card subscription paying for the workspace stops at the same moment, with a
  final invoice for the usage it has not been billed for yet.

### While AWS bills the workspace

- **Settings → Billing** shows the subscription, the AWS account it bills, and
  the worker-minutes reported to AWS this calendar month.
- The minimum is **one worker**. The three-worker minimum below applies only to
  an installation in your own account.
- **Cancel in AWS, not here.** **Manage subscription** opens your AWS
  Marketplace subscriptions. When the subscription ends, no new session starts
  and your data is kept; subscribe again from the listing, or add a card on
  **Settings → Billing**.

## An installation in your own AWS account

### What is different here

Everything runs in **your** AWS account. We never see your prompts, your
repositories or your data, and we never charge your card — AWS meters the
installation and puts it on your AWS bill, under the agreement you accepted when
you subscribed.

There is **no free trial and no card** in this product. The trial and the card
payment screens belong to the product we host; here the subscription you already
have is the arrangement.

### What is metered

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

**Whole minutes, rounded down.** AWS accepts a whole number, so the quantity is
**rounded down** and the allocations are split so their parts still add up to
that whole. The seconds dropped this way are never charged for, and the exact
figure is kept on our side of the record for reconciliation.

### Every company has at least three workers

In this product a company **cannot** be left without a session limit. Unlimited
has no encoding in a metering record — AWS takes a quantity or nothing — so an
unbounded company would run capacity that no record could describe.

The limit is **three workers or more**. A new company starts at three, and a
number below three is refused. A company that was given fewer before this
minimum existed keeps its number until someone changes it.

Your administrator sets each company's limit on **Settings → General → Workers**,
and may raise or lower it at any time, down to three. The change takes effect
immediately, and the hour it happens in is billed for what was actually offered
during each part of it.

### When a bill looks wrong

The installation keeps its own hour-by-hour record of what every company was
offered, independent of what AWS received. If the two ever disagree, that record
is what settles it — ask your operator, or us.

A record AWS rejects is retried from that same ledger for up to six hours, which
is the window AWS still accepts a late record in. After that it is abandoned
rather than retried forever, and the hour is visible as unsent rather than
silently lost.

### Suspended companies

A suspended company runs nothing, so it is metered for nothing. Suspending is
therefore not a way to keep capacity and stop paying for it — the capacity goes
away with the ability to use it.

## See also

- [Session queues](/docs/session-queues) — why a session says **Queued**, and how
  a project reservation differs from a cap
- [Company workspace](/docs/company-workspace) — where a company's settings live
