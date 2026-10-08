# Self-serve signup: how a company gets in, and what it costs

How a stranger turns into a workspace, what bounds them while they are there, and
where payment enters. Written for whoever answers a customer asking "why can't I
sign up", "why did it stop", or "when do you ask for a card".

**Where any of this applies:** the hosted product only (`DEPLOYMENT_MODE=saas`),
and only while `REGISTRATION_ENABLED=true`. A self-hosted operator makes
workspaces in the admin and pays nobody; a Marketplace customer bought their
capacity from AWS before they ever reached us. With the flag off, everything
below is switched off with it — a stranger is refused exactly as before it
existed.

---

## 1. The path in

```
/how-it-works  ──▶  /workspace/new  ──▶  email with a link  ──▶  workspace
   (public)          (public form)        (proof of address)      (admin, onboarding)
```

**`/how-it-works`** is the public page: what the product does, the list price of a
worker, and a calculator driven by the visitor's own numbers. It works out how many
workers their workload needs and carries that number into the form
(`/workspace/new?sessions=N`).

**`/workspace/new`** asks three things: a workspace name, the work email address
the workspace will be owned with, and how many sessions it may run at once.
Someone already signed in is not asked for an address — theirs is the one they
already proved.

**Nothing is written when the form is submitted.** The answers travel in a signed
link to the address that was typed, and opening that link is what proves the
mailbox and creates the company, the account, the admin membership and the session
limit — in one transaction. A link nobody opens leaves nothing behind. The link
lasts 24 hours.

A second click on the same link does not make a second workspace: it collides on
the company's unique domain, which is the same answer by a shorter route.

### What the form refuses

| Refusal | Why |
| --- | --- |
| A domain that is not the one your address is at | A workspace claims a whole domain; claiming one you have no address at is claiming somebody else's |
| A domain another workspace already has | One workspace per domain |
| A public mail service (`gmail.com`, `outlook.com`, `yandex.ru`, …) | The first person to sign up would take the service, funnel every later visitor from it into their workspace, and lock it away for everyone. See `PublicEmailDomains` |
| No session limit, or zero | Everywhere else a company may have no limit and be invoiced for nothing; a company that signs *itself* up may not |

### Where the sign-in screen sends people

Typing a work address at `/login` whose domain no workspace has claimed is not a
refusal where signup is open — it carries through to the form with the address
already filled in.

Someone at a domain that **does** have a workspace, but who is not in it, is
never shown the form: it could only refuse the domain. This happens when the
workspace does not accept the method they signed in with, or when that method did
not prove their address. A redirect sign-in (Google, Microsoft) that ends this
way is not signed in. It lands back on `/login`, which explains what happened.
Anyone already signed in who reaches `/workspace/new` gets the same explanation
in place of the form. If the workspace has proved its domain, the explanation
names the workspace and the sign-ins it accepts that add people from the domain.
Otherwise it names neither and points the person to an invitation, because
auto-join does not run for an unproved domain. The details reach `/login` in the
flash and never in the URL, so a link cannot make the page name a workspace.

---

## 2. Proving the domain

Signing up proves **a mailbox**: that somebody receives mail at an address. It
says nothing about the domain. So a fresh workspace starts with its domain
**claimed but not proved**, and the difference decides one thing:

- **Not proved** — people get in **by invitation**. An admin invites them from
  Members, which is the ordinary path and is unaffected by any of this.
- **Proved** — **domain auto-join** switches on: anyone signing in with an
  address at that domain joins the workspace without an invitation (subject to
  *Accept new people automatically* and to the sign-in methods the workspace
  accepts).

To prove it, the admin publishes a TXT record and presses **Check now** on
Settings → Access:

```
Name:   _aixle-challenge.<domain>
Value:  aixle-domain-verification=<token shown on the screen>
```

A record of its own rather than a value at the root: the root TXT set is shared
with SPF, DMARC and every other vendor's proof, and has a length budget those
already strain. DNS takes minutes to publish, so "not found" means *not yet*.

> **Not fixed by this.** Whoever claimed `acme.com` first still holds the string,
> and the real Acme still cannot sign up — they have to be invited, or an
> operator has to intervene. Ending that means letting several workspaces sit on
> an unproved domain, which the sign-in screen cannot do today: step one resolves
> a workspace *by* domain, and duplicates make it ambiguous.

---

## 3. What a workspace may run

**A worker runs one session at a time.** A workspace with four workers runs four
sessions side by side; the fifth waits. Projects inside it can reserve part of
that limit for themselves, and the rest share what is left.

The limit is the **company admin's** to set, on Settings → General, and they may
raise or lower it whenever they like. They may not clear it: a company with no
limit is one nobody is invoiced for, and that is ours to grant from the admin, not
something a company does to itself. In a company **managed by Aixle** (see
[Billing states](#billing-states)) the limit is read-only for its admins: nobody
pays for it, so raising it would cost them nothing.

**Capacity is the whole price.** No seats, no per-token charge. A worker is
reserved capacity and is charged for every hour it stands ready, whether or not a
session is running on it:

| | |
| --- | --- |
| List price | `PRICING_QUEUE_HOURLY_RATE`, default **$5.00 per worker-hour** |
| One worker, one month | 720 hours — **$3,600** at the default |
| Metering | hourly, time-weighted, exact to the second |
| Invoicing | whole worker-hours; the part hour left at the end of a period rounds **down** |

Time-weighted means half an hour at one worker and half at three is two
worker-hours, not three. Raising or lowering the limit takes effect immediately
rather than next month.

---

## 4. The free allowance

Every new workspace starts with **`TRIAL_QUEUE_HOURS` of free capacity** (default
**100 worker-hours**) and is invoiced for none of it.

**It is a quantity, not a period, and the workspace sets the rate it burns at.**
Ten workers use ten worker-hours an hour, so the same hundred hours that
last one workspace about four days last that one about ten. A bigger limit buys a
shorter trial rather than a larger gift. The limit is theirs throughout — nothing
is capped while the allowance lasts, so they are evaluating the product they are
actually being sold.

A banner sits above every screen while this is running: what has been spent of the
allowance, and how long what is left lasts **at the rate they are running**.

### When it runs out

The hourly meter notices at five minutes past the hour, and the workspace is
**stopped**:

- No new session is admitted. Anything already running **finishes** — nothing is
  killed mid-work for an unpaid bill.
- The banner turns red and says so.
- Nothing is billed for the stopped period either: a workspace that cannot use its
  capacity is not charged for it.

The check is hourly, so a workspace that set a very high limit can spend somewhat
past the allowance before the next run stops it.

### Starting again

An admin adds a card, from the banner or from **Company Settings → Billing**.
Stripe Checkout takes it, and the workspace runs again once Stripe confirms it.
An installation with no Stripe credentials offers no button: there, a platform
administrator moves the company's **Billing state** to `active` in the admin, and
the banner says "talk to us".

### Paying, cancelling, and a payment that fails

The **Billing** tab, admins only, shows where the subscription stands, the current
billing period, and the worker-minutes used so far in it, with an estimate of what
they cost. The estimate is priced the way the invoice is: in packs of 60
worker-minutes, rounded down.

- **Cancelling** takes effect at the end of the current period. Until then the
  workspace runs as before, and its usage up to the end date is billed on the final
  invoice. After it, the workspace stops as it does when the allowance runs out.
  Nothing is deleted, admins can still sign in, and a new card restores access.
  The admin can resume the subscription before the end date. The reason they gave
  is kept, and every admin gets an email.
- **A failed payment** stops the workspace at once. The banner and the Billing tab
  offer the open invoice, not a new card, since a second subscription would bill
  the same minutes twice. Paying it starts the workspace again.

### Billing states

| State | Meaning | Runs | Invoiced |
| --- | --- | --- | --- |
| `trialing` | Spending the free allowance | Its own limit | Nothing |
| `active` | Somebody is paying, including a cancellation not yet due | Its own limit | Everything it is offered |
| `blocked` | Stopped: allowance spent, subscription ended, or a payment failed | Nothing new | Nothing |

A company made in the admin pays the same way a signup does: it starts
`trialing` and needs a session limit. Both are said out loud by the path that
creates the company — the signup form and the admin's create action — rather than
left to a column default, so a trial is never one nobody chose. The column still
defaults to `active`, for the seeds and anything else that makes a company.

**Managed by Aixle** is the other choice on the admin's form, for a company we
carry — ours, a partner's, a pilot. It is never invoiced, never trialing or
blocked, has no Billing tab, and cannot start Checkout. It starts with
**two workers**, and only a platform administrator can change that, from the
admin. Every company that was already `active` with no Stripe customer when the
flag shipped was given it.

---

## 5. What we record

Two ledgers, for two different questions.

**`company_capacity_usages`** — what **every** company was offered, hour by hour,
in worker-seconds. Ours to read: it is what the free allowance is counted from and
what answers "how much has this company used" for an invoice conversation. Written
for trialing and blocked companies too.

**`capacity_meter_reports`** — one row per hour per provider, what is **sent** to
Stripe or AWS Marketplace, with the per-company split. Only companies somebody is
paying for appear in it.

So the allowance needs no counter of its own: what a company has spent is a sum
over the first ledger, and a sum cannot drift from the thing it sums.

---

## 6. The settings that control all of it

| Variable | Default | What it decides |
| --- | --- | --- |
| `DEPLOYMENT_MODE` | `saas` | Whether any of this exists at all |
| `REGISTRATION_ENABLED` | `false` | Whether a stranger may sign a company up |
| `PRICING_QUEUE_HOURLY_RATE` | `5` | The list price shown on `/how-it-works` |
| `TRIAL_QUEUE_HOURS` | `100` | The free allowance |
| `SESSION_PROJECT_CONCURRENCY_DEFAULT` | `4` | What the signup form offers, and a project's share when it has reserved none |

Full descriptions in [reference/configuration.md](../reference/configuration.md).
