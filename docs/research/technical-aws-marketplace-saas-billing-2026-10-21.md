# AWS Marketplace SaaS: a second payer on the hosted installation

**Status:** settled design, no implementation
**Date:** 2026-10-21
**Scope:** selling the hosted product as an AWS Marketplace **SaaS** listing — buyer
registration through `ResolveCustomer`, binding a Marketplace customer to a company,
metering with `BatchMeterUsage`, and consuming subscription notifications. The
installation that sells it is production, which already bills other companies through
Stripe.
**Related:** `docs/design/...` (none yet), `ARCHITECTURE.md` (tenancy through `Company`),
`docs/reference/configuration.md` (the ENV surface), and in the deployment repositories
`marketplace-infra/SAAS_PRODUCT.md` (the listing and the seller account) and
`aixle-infra/doc/helm/stripe-billing.md` (how a third party reaches staging).

---

## Summary

- **`DEPLOYMENT_MODE` stays `saas` and gains no fourth value.** The variable says who runs
  the installation. For this product we run it, exactly as for the Stripe one. A mode
  claiming the whole installation bills through AWS would be false the moment one Stripe
  customer exists beside it, and `aws_marketplace` must keep meaning the container product
  — `requires_bounded_companies?`, `minimum_workers` and the home-page redirect are all
  written for a single-tenant installation in a buyer's own AWS account.
- **The payer becomes a property of the company**, as a new `companies.billing_provider`
  column with values `none` / `stripe` / `aws_marketplace`. This is not a new axis: the
  code already splits payers per company and spells it as the conjunction
  `Deployment.saas? && !managed_by_aixle?`, repeated in four places that do not quite
  agree. `managed_by_aixle` is already a third payer. We are adding a fourth and naming
  the axis.
- **Metering needs almost no new schema.** `capacity_meter_reports` is already unique on
  `(provider, period_start)` and `CapacityMeter#deliver_pending` already filters by
  `adapter.provider`. Today one adapter runs; after this, two do, each claiming its own
  row for the same measured hour. `CapacityWindow` is provider-independent and runs once.
- **The new adapter is `Billing::Meter::Stripe` with the calls swapped.** That adapter
  already bills each company separately out of one row's `breakdown`, skips companies it
  cannot bill, and relies on the provider refusing a duplicate when a half-delivered hour
  is replayed whole. `BatchMeterUsage` has the same properties. The container adapter's
  largest-remainder split is not inherited: it exists only because one call carries one
  quantity, and billing each customer separately removes the problem.
- **The risk is not the meter, it is the five `Deployment` predicates that are really
  per-company questions**, three of which invert for an AWS-billed company on a `saas`
  installation. They move behind one resolved object, `Billing::Payer`, in a PR of its own
  that changes no behaviour.
- **One payer per company is kept by prevention, not by migration.** A Marketplace company
  is never offered a card; every Marketplace arrival is signed out and given a new tenant
  unless its `CustomerIdentifier` is already bound. That removes the branch where a buyer
  is asked which of their companies the subscription belongs to — a question usually put to
  the person least able to answer it, whose wrong answer splits a customer's data in two.
- **Estimate:** six slices, the first of which is a behaviour-free refactor.

---

## 1. Decisions already taken

Settled on 21 October with the seller side; recorded here because the code has to match
them and two of them cannot be revised after publication.

| | |
|---|---|
| Two listings | The container product keeps selling; the SaaS product is added beside it. Both titles have to distinguish "in your own AWS account" from "hosted by us". |
| A dimension of its own | **not** `queue_minute`. `worker_minute` is the proposal, matching the word the product uses everywhere a buyer reads. **The API identifier is immutable after publication**; confirm the exact string before the listing form is filled. |
| Pure usage pricing | No contract dimensions, therefore no `GetEntitlements` and no `entitlement-updated` to consume. The seller-account role carries two permissions, not three. **This does not settle free trials** — a trial is a property of the offer and is compatible with usage pricing. See §10. |
| Unsubscribe blocks and keeps | `billing_state` goes to `blocked` with a reason of its own. Data is untouched; a buyer who subscribes again returns to their workspace. |
| **There is no payer migration** | Not a mechanism that moves a company from one payer to the other, but rules that stop a company from ever having two. Settled 21 October, after the question was raised on a call and answered "let us have that problem first" — which is correct, and is an argument for prevention rather than for machinery. |
| **A Marketplace company cannot attach a card** | Where AWS bills, Checkout is not offered at all. One-way and cheap: it is a refusal on screens that already have a guard. |
| **Every arrival creates a new tenant** | A visitor arriving from Marketplace is signed out and led to workspace creation, whoever they are and whatever they already have — unless the identifier is already bound. See §5.2. |
| **The payer is shown on every active company** | `stripe` or `aws`, in the admin and on the company's own billing screen. Two payers on one installation is invisible until somebody can see which is which. |

The dimension string is the one thing publication makes permanent. It must match the new
adapter's constant character for character, and it is a **new** constant beside
`Billing::Meter::AwsMarketplace::DIMENSION` rather than that constant changed — the
container product's `queue_minute` is published and cannot move.

---

## 2. Why this is not a deployment mode

`Deployment.mode` (`app/services/deployment.rb:30`) is one string for the whole
installation, and `Billing::CapacityMeter::ADAPTERS` (`capacity_meter.rb:14-18`) picks the
meter from it. So an installation bills exactly one way today.

Production is the installation that would sell this, and it already holds companies paid
for through Stripe and companies carried by us. A Marketplace customer there is a third
kind **beside** the other two, not instead of them.

Adding `AWS_MARKETPLACE_SAAS` to `MODES` would be the tempting move and the wrong one,
twice over:

- it would be a claim about the installation that is false for most of its companies;
- `Deployment::AWS_MARKETPLACE` would then have a sibling that looks like a variant of it
  and is not. The container product's mode means *the customer runs this in their own
  account*. Its predicates — a limit on every company, a minimum of three workers, no
  marketing page — are correct there and wrong here.

---

## 3. What already exists, and what it is missing

Measured, at `develop` on 21 October.

**The per-company payer split already exists, unnamed.** These four places each read
"the installation is hosted by us, *and* this particular company pays":

```ruby
# app/models/session_concurrency_limit.rb:117
elsif Deployment.saas? && Company.exists?(id: scope_id, managed_by_aixle: false)

# app/models/company.rb:269
elsif Deployment.saas? && !managed_by_aixle? && !leaving_management?

# app/controllers/web/company/application_controller.rb:25
can_manage_billing: Deployment.saas? && !current_company&.managed_by_aixle? && ...

# app/models/company.rb:116
scope :billing_billable, -> { where(billing_state: "active", managed_by_aixle: false) }
```

They do not agree — one adds `&& !leaving_management?`, one goes through a scope, one
re-queries the company it already has. Naming the axis fixes that as a side effect.

**`Billing::Meter::Stripe` already bills many companies from one ledger row.** It iterates
`report.breakdown_minutes`, looks each company's `stripe_customer_id` up, skips the blanks
as `unbilled`, and returns a synthetic summary string as the row's `external_id`
(`app/services/billing/meter/stripe.rb:33-56`). One meter event per company per hour,
keyed on company and hour so a replay is refused rather than double-charged.

**What is genuinely absent:** no `ResolveCustomer`, no `BatchMeterUsage`, no token
handling, no customer-to-company mapping, no SNS consumption. The gem is not absent —
`aws-sdk-marketplacemetering` (`Gemfile:211`, locked at 1.107.0) is the whole AWS
Marketplace Metering Service, whose four operations are `MeterUsage`, `BatchMeterUsage`,
`RegisterUsage` and `ResolveCustomer`. No new dependency is needed. `GetEntitlements` is
a different service and, under pure usage pricing, is not wanted.

---

## 4. The payer becomes a property of the company

### 4.1 `companies.billing_provider`

A string column, `null: false`, default `"none"`, values `none` / `stripe` /
`aws_marketplace`. `none` covers both a company we carry and a company that has never
paid.

Why a column rather than inferring the payer from which key is present
(`stripe_customer_id` against a Marketplace customer row): the invariant that matters is
**exactly one payer per company**, and that is checkable on one column and not across two
tables. Double billing is the one failure a customer notices immediately and that cannot
be undone quietly.

Backfill is from what is already true: `stripe_customer_id` present → `stripe`, otherwise
`none`. No company changes behaviour on the migration.

`managed_by_aixle` stays as it is. It answers a different question — whether we forgive
the bill — and it already forces `billing_state: "active"`
(`company.rb:205-207`). Folding it into `billing_provider` would be a larger refactor of
the Stripe lifecycle for no gain here.

**The column is shown, not only stored.** Every active company displays its payer —
`stripe` or `aws` — in the admin panel, and on the company's own billing screen. Decided
21 October, and it is not cosmetic: the moment two payers share an installation, "who is
billing this customer" stops being answerable from the fact that they are paying. An
operator looking at a company that owes money needs to know which system to open before
they can do anything at all, and the only alternative is inferring it from which column
happens to be filled — which is precisely the inference §4.1 exists to replace.

It ships in slice 1, with the column, rather than with the Marketplace code. On a
single-payer installation it reads `stripe` everywhere and looks pointless; that is the
cheapest moment to get it in front of the people who will later rely on it.

### 4.2 `Billing::Payer`

A small object resolved from a company, answering the questions that are per-company and
are currently asked of `Deployment`:

```ruby
payer = Billing::Payer.for(company)

payer.provider            # "none" | "stripe" | "aws_marketplace"
payer.bills?              # is anyone invoiced for this company's capacity
payer.owns_capacity?      # may a company admin move the number
payer.requires_bound?     # must the company carry a limit
payer.minimum_workers     # 1, or 3 for a Marketplace company
payer.trial?              # does the free allowance apply
```

`Deployment` keeps describing the installation and supplies the default for a company
with no provider of its own, so `self_hosted` and the container `aws_marketplace` mode
answer exactly as they do today.

The twenty-odd call sites listed in §4.3 then read `Billing::Payer.for(company).…`
instead of a conjunction of two `Deployment` predicates and a column.

### 4.3 What inverts for an AWS-billed company

The honest list of what answers **the opposite** of what it answers today for a company on
a `saas` installation:

| Question | Today on `saas` | An AWS-billed company needs | Call sites |
|---|---|---|---|
| `requires_bounded_companies?` | `false` | **`true`** — "unlimited" has no encoding in a metering record | 3 |
| `minimum_workers` | `1` | **`3`** (`MARKETPLACE_MINIMUM_WORKERS`) | 7 |
| `Billing::Trial` applies | yes | **no** — a Marketplace product has no free allowance | 4 |
| `HostedBillingOnly` | allows | allows, but with no card and no Checkout | 4 |

Three things that are **already right** and need no work, each verified rather than
assumed:

- **`Web::Company::SettingsPolicy#manage_capacity?`** is `admin? && !managed_by_aixle?`
  (`settings_policy.rb:17`). A company admin already moves their own number in every
  deployment, which is exactly what a metered product needs: raising workers is a
  purchase.
- **`Deployment.customer_owns_capacity?`** has no call sites outside its own file. It is
  dead code and should be deleted rather than carried into `Billing::Payer`.
- **`Billing::EffectiveCapacity.ceilings`** already clamps a `blocked` company to `0` on
  any `saas` installation (`effective_capacity.rb:19-26` through
  `Trial.ceiling_for`, which answers `0` for `blocked` and nothing for `trialing`), and
  the admission drain reads that clamp. So "unsubscribe blocks" needs no new branch on the
  session admission path: writing `billing_state` is the whole of it. Note the other half
  of that method — `trialing` deliberately has no ceiling — is Stripe-shaped and is part of
  what §4.3 says must not reach a Marketplace company.

---

## 5. Binding a buyer to a company

This is the part with the risk in it, and none of it is an AWS call.

**AWS does not tell us who arrived.** `ResolveCustomer` returns a `CustomerIdentifier`,
the product code and the buyer's AWS account id. No name, no address, no organisation. The
person in the browser is signed in to AWS, not to us.

### 5.1 The registration endpoint

AWS redirects the buyer's browser to our fulfilment URL with a form-encoded `POST`
carrying `x-amzn-marketplace-token`. It is a cross-origin, cookie-less, CSRF-tokenless
POST that must end in a rendered page, not JSON.

The closest existing shape is `Webhooks::StripeController` — an unauthenticated POST from
a third party that grants paid status — but that one is `ActionController::API`, which
cannot render the app. This endpoint wants `ActionController::Base` with a scoped
`skip_before_action :verify_authenticity_token`, which is the
`Web::OidcSessionsController:14` pattern, plus a CORS entry in the shape of the YouTrack
pairing rule (`config/initializers/cors.rb:22-26`).

The token is single-use and short-lived, so the exchange happens on arrival; what is
carried onward is the resolved `CustomerIdentifier`, not the token.

**The POST's fields are fixed, and there is no way to add one.** Established 21 October
against the Seller Guide, because the design would have been different if it were not:

| Field | When |
|---|---|
| `x-amzn-marketplace-token` | always; an opaque string, exchanged through `ResolveCustomer` |
| `x-amzn-marketplace-offer-type` | only when the offer is a free trial, with the value `free-trial` |

Everything else — the buyer's AWS account id, the `CustomerIdentifier`, the product code
— comes back from `ResolveCustomer`, not from the form. There is no screen anywhere in
Marketplace where a buyer could type a company name, an email or a code that would reach
us in this request.

**This turns §5.2 from a preference into the only option.** That section argues for asking
on our own page rather than letting a buyer bring an answer with them; it turns out a buyer
cannot bring one. The argument stands, but it is no longer the reason.

**`free-trial` is persisted, whatever we decide about trials.** An earlier draft of this
section called the parameter a tripwire and had the endpoint refuse a registration that
carried it, on the reasoning that pure usage pricing meant no trial. **That inference was
wrong.** The pricing model and the free trial are independent: a free trial is a property
of the *offer*, and a usage-priced SaaS offer may carry one. (What AWS does restrict —
answered by Seller Operations on 29 September — is free trials on **AMI** products using
the Metering Service. It has never applied here.) Refusing would have broken a real
purchase.

Whether we will offer one is **not decided** — see §10. What the endpoint does is decided,
and it is the same under either answer: **read the parameter and store it**. This is the
only moment it arrives for free, the token is single-use, and the POST does not happen
again. Losing it is unrecoverable; keeping it costs a column.

Our own `Billing::Trial` is a different thing entirely — a Stripe-shaped allowance in
queue-hours — and §4.3 already says it must not reach a Marketplace company. Two trial
mechanisms on one company would each believe they were the one in charge.

Two workarounds exist for carrying per-purchase context and neither is taken:

- **A static query string on the fulfilment URL.** One URL per listing, so it is a
  constant, not per-purchase. We have nothing to put in it. *Unverified either way:*
  whether AWS preserves a query string on the URL it posts to has not been tested, and it
  would be a silent failure if it does not.
- **`SearchAgreements` to find the buyer's offer.** A second AWS API, a second IAM
  permission and a second service to be unavailable, in exchange for context we do not
  need: under pure usage the price lives on the offer and AWS applies it without the
  caller knowing, which is measured — the container product's metering survived a change
  of agreement without the application noticing
  (`marketplace-infra/BEFORE_PUBLISHING.md`). The offer identifier arrives free in the SNS
  notifications anyway (§8), so storing it from there costs nothing and asking for it
  costs a dependency.

### 5.2 Every arrival is a new tenant, except a bound one

An earlier draft of this section had four arrival cases, one of which asked the visitor
whether to attach the subscription to a company they already administer. **That branch is
gone.** Settled 21 October: a visitor arriving from Marketplace is signed out and led to
workspace creation, whatever account they already hold.

So there are two paths, and which one is taken is decided by the database, not by the
visitor:

| State of the `CustomerIdentifier` | What happens |
|---|---|
| Not bound | sign the visitor out, carry the resolved customer forward, land on workspace creation. A new company, bound to the identifier on creation |
| Already bound | **never create.** This is the return path — Manage subscriptions reissues a token every time, and a colleague may arrive with one of their own. Land on sign-in for the company the identifier holds |

Why signing out is right rather than merely simple: the question "attach this subscription
to which of your companies?" is asked of somebody who, in AWS, is usually procurement or a
cloud administrator and will never use the product. They are the worst-placed person in the
organisation to answer it, and a wrong answer splits a customer's data across two tenants
with no way back. Removing the question removes the failure.

What it costs is a second tenant for a customer who already had one. That is the trade
being made deliberately, and §10 is what remains of it.

**A token is not a membership grant.** An arrival whose identifier is already bound is
taken to sign-in, not joined to that company automatically. Whoever holds the AWS account
is not necessarily someone we should admit to a workspace, and membership keeps coming the
way it already does — an invitation, or a verified email domain.

The existing signup already has the right carrier for the round trip:
`WorkspaceSignupTicket` (`app/controllers/web/workspaces_controller.rb:47,87`) is a signed
ticket that survives an email round-trip and ends in company creation. A resolved
`CustomerIdentifier` rides it the same way. Note that this path must work with
`Deployment.self_serve_signup?` unchanged: on production that predicate is `false`
(`REGISTRATION_ENABLED` is unset), and a Marketplace arrival has to create a company
anyway — the subscription is the authorisation that a stranger signing up does not have.

### 5.3 Idempotence is the whole of it

A buyer can reach the registration page again from Manage subscriptions, and AWS issues a
fresh token each time. A second arrival that creates a second company is the easiest bug to
write here and the hardest to unpick afterwards, because by then both have data in them.

`CustomerIdentifier` is the key: unique, bound to exactly one company, written once.

### 5.4 Registration and subscription arrive in either order

AWS sends `subscribe-success` to SNS on its own schedule, and a buyer can subscribe and
never finish registering. That leaves a customer who is being billed and has no account —
a state that has to be **visible to us deliberately**, because otherwise the first report
of it is a complaint.

The opposite happens too: somebody registers before the subscription is confirmed and is
entitled to nothing yet.

---

## 6. Data model

```
companies
  billing_provider      string  not null  default "none"   # none | stripe | aws_marketplace

marketplace_customers
  customer_identifier   string  not null  unique           # from ResolveCustomer
  product_code          string  not null
  aws_account_id        string  not null
  company_id            bigint  null, unique when present  # null until registration binds it
  subscription_state    string  not null                   # pending | active | unsubscribe_pending | unsubscribed
  offer_identifier      string  null                       # from the SNS notification, never asked for
  registered_offer_type string  null                       # x-amzn-marketplace-offer-type as it arrived, or null
  subscribed_at         datetime
  unsubscribed_at       datetime
```

`registered_offer_type` stores the string as it arrived rather than an interpretation of
it, because §10 has not decided what a trial means for us yet and a boolean would bake in
an answer we do not have.

`offer_identifier` is written when a notification carries it and is read by nobody in the
billing path — it is there so that "which deal is this customer on" is answerable during a
support conversation without calling a second AWS API. Nothing should start depending on
it being present: it arrives with the notification, and a customer whose registration ran
before any notification has none yet.

`company_id` is nullable because §5.4 says a subscription can exist before anybody has
registered; it is unique so one company never holds two subscriptions. The unique index on
`customer_identifier` is what makes §5.3 true in the database rather than in a service
object.

`Company::BILLING_BLOCK_REASONS` is `%w[allowance canceled payment_failed]`, all three
Stripe-shaped. A Marketplace unsubscribe wants a fourth value rather than borrowing
`canceled`.

---

## 7. Metering

### 7.1 Two providers, one measured hour

`Billing::CapacityMeter` stops taking a single adapter. It measures the hour once —
`CapacityWindow` is about capacity offered and knows nothing about who pays — and then
runs each enabled provider, each claiming its own `CapacityMeterReport` row for that hour.

The table and the delivery loop already support this: `(provider, period_start)` is the
uniqueness key, and `deliver_pending` already scopes `where(provider: adapter.provider)`.
Two rows an hour is what the schema was built for; only the orchestration assumed one.

One change of meaning: `Billing::Meter::Stripe` selects its companies by the presence of
`stripe_customer_id`. It must select on `billing_provider` instead, or an AWS-billed
company is silently counted as `unbilled` on the Stripe row — which reads as "nobody pays
for this one" when AWS does.

### 7.2 The adapter

`Billing::Meter::AwsMarketplaceSaas`, built from `Meter::Stripe` rather than from
`Meter::AwsMarketplace`:

- iterate the row's `breakdown_minutes`;
- map company → `CustomerIdentifier`, skipping companies whose provider is not
  `aws_marketplace` and counting them, as Stripe counts its own;
- floor each customer's minutes — `UsageRecord.Quantity` is an integer, and because each
  customer is billed separately there is no remainder to redistribute;
- send in slices of 25, the call's limit;
- resolve each record's outcome from the response. `BatchMeterUsage` answers with
  `Results` and `UnprocessedRecords`, and a repeated `(customer, dimension, hour)` comes
  back as a duplicate rather than a failure — which is what makes replaying a whole hour
  safe, exactly as Stripe's `identifier` does;
- return a summary string as `external_id`, in the shape Stripe's already uses.

The hourly schedule, the `max_attempts: 1` retry policy and the six-hour replay window are
unchanged and are the reasons they already say they are
(`app/temporal/schedules.yml:225-234`, `capacity_meter_report.rb:10`).

### 7.3 Credentials: the one genuinely new failure mode

The container product's client is `::Aws::MarketplaceMetering::Client.new` with no
arguments — the pod's own IRSA identity, in the buyer's own account
(`marketplace_metering_client.rb:59-63`). That works because the pod and the subscription
are the same account.

Here they are not. The call must be signed by the account that owns the listing
(`076388571405`) while the application runs in `541894707537`, so the client assumes a
role in the seller account and refreshes it. That is a different client construction and a
new way to fail that has nothing to do with metering: a credential error and a metering
rejection must not be reported as the same thing, because one is ours to fix in minutes
and the other is a listing problem.

The region is explicit, not inherited. The pod's default region is not necessarily the
listing's.

---

## 8. Subscription notifications

Four, under pure usage pricing: `subscribe-success`, `subscribe-fail`,
`unsubscribe-pending`, `unsubscribe-success`. Not `entitlement-updated`, which belongs to
contract pricing we are not selling.

They arrive on SNS topics owned by the seller account and are read from an SQS queue in
ours. Consuming them is not bookkeeping: an unsubscribe nobody reads means serving a
customer who has stopped paying.

`subscribe-success` for a `CustomerIdentifier` nobody has registered is §5.4's state, and
it needs somewhere to be seen. The admin panel is the obvious home; what it must not be is
a log line.

The message carries the offer identifier alongside the customer identifier and the product
code, which is the only per-deal context that reaches us anywhere. It is stored (§6) and
otherwise ignored. *To verify:* that it is present on every one of the four actions and not
only on `subscribe-success` — the column is nullable either way, so this decides a comment
rather than a design.

---

## 9. Where this is tested

Staging, and it is already shaped for it — `DEPLOYMENT_MODE: saas`,
`REGISTRATION_ENABLED: "true"` and a Stripe test-mode price are all set
(`aixle-infra/kube/helmfile/values/aixle-app/staging.yaml`). So the Marketplace path stands
up beside a live Stripe path there, which is the per-company-payer problem in miniature on
a real environment.

Two things to know before planning the first deploy:

- **The deploy workflow takes any flow branch whose CI is green on staging**
  (`palad-ai/palad-app`, `.github/workflows/deploy.yml`), so a feature branch can be
  exercised there without a release tag.
- **Migrations run before the new code is promoted**, so for the few minutes between them
  the new schema is served by the old code. Every migration here is additive, and the code
  that requires a new column ships in the slice after the one that adds it.

The public door is the constraint. `staging.flow.aixle.com` resolves publicly but answers
`401` behind basic auth; `webhooks-staging.flow.aixle.com` is the auth-free host and routes
exactly three path prefixes, each with a `webhook-host-rewrite` middleware. The Marketplace
registration POST needs a fourth, which is the same change SCIM and the YouTrack pairing
API each made for the same reason.

A tester will meet one basic-auth prompt partway through the flow, when the app redirects
from the auth-free host to the app's own. That is expected on staging and not a defect.

On the AWS side this wants a `[TEST]` SaaS product with Limited visibility and an
allowlisted buyer account, pointed at staging — the shape the container product already
proved — rather than the real draft, which carries the real product code and the real
marketing copy.

---

## 10. Open questions

- **The Stripe subscription left behind.** This is what remains of the payer-migration
  question after §1 answered it, and it is the one thing in this document with no
  recommendation I am confident in.

  An existing Stripe customer buys through AWS. §5.2 gives them a **new, empty** tenant.
  Their work is still in the old one, which is still subscribed and still charged. The
  instinct is to cancel that subscription — and it is the wrong move as stated, because
  cancelling it sets `billing_state: "blocked"` with reason `canceled`, which clamps that
  company to a ceiling of `0`. The customer would lose access to all their data on the day
  they started paying us more.

  What I would do instead, and would rather have argued about than assumed: **cancel
  nothing automatically.** Surface the overlap and let a person handle it, because the
  resolution is a conversation — do they want the old workspace moved, abandoned, or kept
  running alongside? — and none of the three is a safe default.

  There is a usable detector, and it should ship with the registration slice rather than
  after it: the new company's `email_domain` matching an existing company's. That is
  already the key the application joins people to companies on, and it is the only signal
  we have that two tenants are one organisation. Without it the overlap is invisible until
  the customer writes in, which is the same failure mode as the unregistered subscriber in
  §5.4.

  Not urgent, and deliberately so: nothing can reach this state until the registration
  slice exists.
- **Free trials: whether we offer one, and what it means if we do.** Raised on a call as a
  possibility, not settled. It is listed here rather than in §1 because the registration
  endpoint behaves identically either way (§5.1 stores the parameter), so nothing is
  blocked — but three things have to be answered before any free-trial offer is created,
  and only the first of them is AWS's.

  **Does metering during a trial charge the buyer?** Unknown, and the one question here
  that we cannot answer ourselves. Either AWS zero-rates usage for the trial term and we
  meter as normal, or it does not and `BatchMeterUsage` bills somebody who was promised
  nothing. This goes to Seller Operations, the channel that answered the eleven questions
  in `marketplace-infra/SELLER_OPERATIONS.md`, **before** an offer exists rather than
  after. Guessing it is the expensive direction of a mistake.

  **A trial on this product costs us, and the buyer sets the number.** This is the
  consequence nobody has named yet, and it is not an AWS question. On the container
  product a trial runs in the buyer's own account on their own hardware, so capacity costs
  them whatever we charge. Here the workers run on our cluster. Meanwhile
  `Web::Company::SettingsPolicy#manage_capacity?` lets a company admin raise their own
  number — correct for a metered product, where raising it raises the bill, and **not**
  correct during a trial, where it raises nothing but our costs. `MARKETPLACE_MINIMUM_WORKERS`
  is 3; nothing stops a trialling buyer from setting 50 on the first day.

  So a free trial needs a ceiling the customer cannot raise, for its duration. The
  mechanism already exists and is the one §4.3 says must not reach a Marketplace company:
  `Billing::EffectiveCapacity.ceilings`. If trials happen, that sentence needs refining
  rather than reversing — our queue-hour allowance still must not apply, but the clamp it
  rides on is exactly what a trial wants.

  **How a trial ends.** Whether a notification arrives, or the end is a date we have to
  hold ourselves, is unverified. It decides whether trial expiry is an event we consume or
  a sweep we run.
- **The reverse: a Marketplace customer who wants to pay by card.** Closed by §1 in one
  direction only — they cannot attach a card while AWS bills them. What they do after
  unsubscribing, when their company is `blocked` and the Checkout refusal is still in
  force, is not written down anywhere. The rule probably wants to be "the refusal is on
  an active Marketplace subscription, not on a company that once had one", but that
  sentence has not been checked against the unsubscribe states in §8.
- **The exact dimension identifier.** `worker_minute` is the proposal. Immutable after
  publication, and it must match the adapter's constant exactly.
- **Where a subscribed-but-unregistered customer is shown**, and who is expected to look.
- **One service account or two** for the right to assume the seller role. The app's pods
  carry exactly one IAM role today and a service account annotation holds one role ARN, so
  this is a choice rather than a line of Terraform.
- **Whether the registration page may live on the production domain**, and what AWS
  requires of it during assessment.

---

## 11. Implementation breakdown

| | Slice | Why here |
|---|---|---|
| 1 | `billing_provider` + `Billing::Payer` + the payer shown on every active company, behaviour otherwise unchanged | The riskiest change, because it touches the live Stripe path. Alone and first, so a staging failure is unambiguous |
| 2 | `marketplace_customers`, the registration endpoint, `ResolveCustomer`, the sign-out-and-create flow, the Checkout refusal, and the duplicate-domain detector from §10 | Needs slice 1's column to bind to. The detector ships here rather than later: after this slice the overlap it finds can exist |
| 3 | `Billing::Meter::AwsMarketplaceSaas` + the assumed-role client | Independent of 2 — can be proved against a hand-bound customer row |
| 4 | Two providers in one run of `CapacityMeter` | Separated from 3 so a metering bug and an orchestration bug cannot be confused |
| 5 | SQS consumption and the subscription states | Needs the queue, which is `aixle-infra` work |
| 6 | Staging ingress, config, and a live run against a `[TEST]` listing | The first time any of it meets AWS |

Slices 1, 3 and 4 are provable in the test suite. Slices 2, 5 and 6 are not finished until
they have run on staging against a real subscription.
