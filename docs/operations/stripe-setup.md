# Stripe setup

What has to exist in the Stripe account before metered capacity can be billed,
and how to hand this application the credential it needs.

> **Status: built, and live mode not switched on.** The application creates
> customers, opens Stripe Checkout, sends meter events and acts on webhooks. What
> remains is a live-mode account: the objects below exist in test mode and do not
> carry over.

---

## 1. Work in test mode

Everything below is done in **test mode** (the toggle at the top right of the
dashboard, or inside a **Sandbox** in the newer interface). Nothing is created in
live mode until the whole flow has been driven end to end on test.

## 2. Issue an API key

**Developers → API keys** — <https://dashboard.stripe.com/test/apikeys>

Either take the **Secret key** (`sk_test_…`), which is scoped to the test sandbox
and touches no real money, or create a restricted key (`rk_test_…`) with **Write**
on exactly these and `None` on everything else:

- Billing Meters
- Meter Events
- Products
- Prices
- Customers
- Checkout Sessions
- Billing Portal
- Subscriptions
- Webhook Endpoints

A restricted key is the better habit: it is revoked with one button and is
attributable to the integration rather than to a person.

> **Never a dashboard login.** A username and password is a named human's full
> access to the account — live mode, payouts, team management — and Stripe
> requires 2FA on it anyway. The key above is the credential for this job.

> **Already created in test mode** (account `acct_1UIwA0RfWGHL113S`):
>
> | | |
> | --- | --- |
> | Meter | `mtr_test_61VUFBw05qIHrGlrX41RfWGHL113SAXI` |
> | Product | `prod_VLYLkzDfhdW0A4` |
> | Price | `price_1UKrEiRfWGHL113SKW7Snqaa` |
>
> Steps 3 and 4 are the record of how, and what to repeat in live mode.

## 3. The meter

**Billing → Meters → Create meter**

| Field | Value |
| --- | --- |
| Event name | `queue_minutes` |
| Aggregation | Sum |
| Value field | `value` |
| Customer mapping | `stripe_customer_id` |

Queue-**minutes**, not hours: capacity is measured exactly to the second
(`capacity_meter_reports.quantity_seconds`) and Stripe accepts a fractional value,
so minutes are sent unrounded and nothing is lost at this edge. One queue-hour is
60 units.

## 4. The product and its price

**Product catalogue → Add product**

| Field | Value |
| --- | --- |
| Name | Aixle Flow capacity |
| Pricing model | Usage-based, metered |
| Meter | `queue_minutes` |
| Price | `PRICING_QUEUE_HOURLY_RATE` ÷ 60 per unit — **$0.0833333** at the default $5/queue-hour |
| Billing period | Monthly |

Keep the price and `PRICING_QUEUE_HOURLY_RATE` in step: the second is what
`/how-it-works` quotes to visitors, the first is what they are actually charged.
They are two copies of one number and will drift if nobody is watching.

### Everyone pays in the price's currency

Stripe's Adaptive Pricing converts the checkout page into the visitor's local
currency from their IP — a customer in Jakarta was quoted rupiah at Stripe's own
rate. That is a second price nobody here set and nobody here can reconcile
against the queue-minutes we metered, so the application turns it off per session
(`adaptive_pricing: { enabled: false }`). It is set in code rather than in the
dashboard so it is version-controlled and survives somebody changing a setting.

## 5. The webhook

**Developers → Webhooks → Add endpoint**, pointed at `https://<host>/webhooks/stripe`,
subscribed to:

- `checkout.session.completed` — a card has been added; the company moves to
  `active`
- `customer.subscription.updated`, `customer.subscription.deleted` — a
  subscription lapsing moves it back
- `invoice.payment_failed` — what makes a company `blocked` for non-payment
  rather than for a spent allowance

The signing secret (`whsec_…`) is shown once on creation. For local development
use `stripe listen --forward-to localhost:4000/webhooks/stripe` instead, which
prints its own.

**Not yet created:** the endpoint needs a public host, which is a deployment
decision rather than a code one. Until it exists, a card added through Checkout
is taken by Stripe and the company is not moved to `active` — the webhook is the
only thing that does that.

### What each event does

| Event | Effect |
| --- | --- |
| `checkout.session.completed` | The company becomes `active`, and its subscription id is recorded |
| `customer.subscription.updated` | Follows the status: `active`, `trialing` and `past_due` keep running; anything else stops |
| `customer.subscription.deleted` | The company is stopped |
| `invoice.payment_failed` | The company is stopped |

`past_due` deliberately keeps running. A failed payment starts a dunning cycle
that usually ends in payment, and stopping a customer's work on the first retry
is a worse mistake than carrying them for a few days.

A company stopped this way goes to `blocked`, not back to `trialing`: the free
allowance was spent once and cancelling does not give it back.

---

## What the application reads

| Variable | Purpose |
| --- | --- |
| `STRIPE_SECRET_KEY` | The key from step 2 |
| `STRIPE_WEBHOOK_SECRET` | The signing secret from step 5 |
| `STRIPE_PRICE_ID` | The metered price from step 4 |

A Stripe customer is created **lazily**, when a card is first added — not at
signup. Signup already waits on an email round trip, and a Stripe outage must not
be able to stop someone registering.

Without all three, nothing calls Stripe at all: no card can be added, the banner
offers no button, and capacity is still measured and recorded — only never sent.
That is the state every self-hosted installation is in permanently.

### Replays cannot bill twice

Each meter event carries an identifier built from the company and the hour, and
Stripe refuses a second event with an identifier it has already seen. That
refusal is read as "recorded", not as a failure, which is what makes the capacity
ledger's replay safe: an hour that failed halfway is resent in full and only the
missing parts land.

## Registration cannot open without this

`REGISTRATION_ENABLED=true` on a hosted deployment with no Stripe key **refuses
to boot** (`config/initializers/required_env.rb`). The two switches are the kind
that drift apart quietly and are found out by a customer: people sign up, spend
the free allowance, and reach a stop with no card to add and no button to press.

So the order is: configure Stripe, then open registration. Never the other way,
and the deploy will not let you.

## Before switching live mode on

- [ ] The whole flow driven on test: signup → allowance spent → blocked → card
      added → running again
- [ ] Meter, product and price recreated in live mode (test-mode objects do not
      carry over)
- [ ] Live webhook endpoint created and its secret deployed
- [ ] `PRICING_QUEUE_HOURLY_RATE` and the live price checked against each other
- [ ] A test invoice read end to end and its queue-minutes reconciled against
      `company_capacity_usages` for the same hours

## Related

- [product/self-serve-signup.md](../product/self-serve-signup.md) — the customer's
  side: what is free, what stops, and when a card is asked for
- [reference/configuration.md](../reference/configuration.md) — every variable
  named here
