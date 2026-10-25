# AWS Marketplace SaaS: a second payer on the hosted installation

**Status:** settled design, no implementation
**Date:** 2026-10-21
**Scope:** selling the hosted product as an AWS Marketplace **SaaS** listing — buyer
registration through `ResolveCustomer`, binding a Marketplace customer to a company,
metering with `BatchMeterUsage`, and consuming subscription notifications. The
installation that sells it is production, which already bills other companies through
Stripe.
**Related:** `docs/design/...` (none yet), `ARCHITECTURE.md` (tenancy through `Company`),
`docs/reference/configuration.md` (the ENV surface), and two documents in the private
repositories: the listing repository's note on the SaaS listing and the seller account, and
the infrastructure repository's note on how a third party reaches staging.

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
| A dimension of its own | **not** `queue_minute`. `worker_minute`, decided 22 October, matching the word the product uses everywhere a buyer reads. **The API identifier is immutable after publication**, so this string is now fixed: `Billing::Meter::AwsMarketplaceSaas::DIMENSION` and the listing form must agree exactly. |
| Pure usage pricing | No contract dimensions, therefore no `GetEntitlements` and no `entitlement-updated` to consume. The seller-account role carries two permissions, not three. **This does not settle free trials** — a trial is a property of the offer and is compatible with usage pricing. See §10. |
| Unsubscribe blocks and keeps | `billing_state` goes to `blocked` with a reason of its own. Data is untouched; a buyer who subscribes again returns to their workspace. |
| **Our own trial is off wherever a payer is attached** | Stripe or AWS alike. A Marketplace free trial, if one is ever offered, is AWS's discount on usage we report as normal — not a mode of ours. The two never coexist, so no company is ever in two trials. See §10. |
| **There is no payer migration** | Not a mechanism that moves a company from one payer to the other, but rules that stop a company from ever having two. Settled 21 October, after the question was raised on a call and answered "let us have that problem first" — which is correct, and is an argument for prevention rather than for machinery. |
| **A Marketplace company cannot attach a card** | Where AWS bills, Checkout is not offered at all. One-way and cheap: it is a refusal on screens that already have a guard. |
| **Every arrival creates a new tenant** | A visitor arriving from Marketplace is signed out and led to workspace creation, whoever they are and whatever they already have — unless the identifier is already bound. See §5.2. |
| **The payer is shown on every active company** | `stripe` or `aws`, in the admin and on the company's own billing screen. Two payers on one installation is invisible until somebody can see which is which. |
| **The key is `LicenseArn`, not `CustomerIdentifier`** | Forced, not chosen. AWS requires **Concurrent Agreements** of every SaaS product created after 1 June 2026, and our draft was created on 19 October. Under it `CustomerIdentifier` is not populated, `BatchMeterUsage` requires a `LicenseArn` per record and does not accept a product code, and one AWS account may hold several live agreements for the same product. See §3.1. |

The dimension string is the one thing publication makes permanent. It must match the new
adapter's constant character for character, and it is a **new** constant beside
`Billing::Meter::AwsMarketplace::DIMENSION` rather than that constant changed — the
container product's `queue_minute` is published and cannot move.

**Corrected on 23 October, against the real listing.** `LicenseArn` is the key,
but it is not sufficient on its own: a usage record carrying only `LicenseArn`
comes back

```
ValidationException: CustomerIdentifier or CustomerAWSAccountId is required in Usage record
```

so the buyer's account id travels beside it. That is not the second keying this
section warns about -- `ProductCode` is -- and it does not double-bill: the
account says who, the licence says which of their agreements. `ResolveCustomer`
returns it and §6 already stores it, so nothing new had to be learned about the
customer; the adapter simply was not sending what it already had.

This was invisible to every test. The contract test asserted the record we
*intended* to send, and the fake answered whatever it was given. Only the live
call could say that AWS wanted more.

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

## 3. What the ground is

### 3.1 Concurrent Agreements, which this product cannot opt out of

Read out of the Seller Guide on 21 October, after an earlier draft of this document had
been written against the older integration. It is the single largest correction here, and
it arrives before everything downstream because the key every table hangs off changes.

AWS now supports **Concurrent Agreements** — "multiple active purchases for the same
product within a single AWS account". It is **opt-in for listings created before 1 June
2026 and required for every SaaS product created after it**. Our draft was created on
19 October 2026, so it is enabled by default and there is nothing to decide. (The entity id lives in
the listing repository, which is where seller-account identifiers belong.)

What changes, from the Seller Guide and the Ruby SDK's own signatures:

| | Old integration | This product |
|---|---|---|
| `ResolveCustomer` returns | `CustomerIdentifier`, `ProductCode` | also `CustomerAWSAccountId`, `LicenseArn`, `metadata.agreement_id`. "For new SaaS product integrations, the `CustomerIdentifier` field is not populated" |
| The tenant key | `CustomerIdentifier`, one per account | **`LicenseArn`, one per agreement.** An account may hold several at once |
| `BatchMeterUsage` | `product_code` + `customer_identifier` per record | `license_arn` per record. "For opted-in products, `LicenseArn` is required, and `ProductCode` is not supported" |
| Notifications | SNS | EventBridge. See §8 |

Two consequences worth stating plainly because they are easy to miss:

**The one-per-hour metering limit applies per method.** The Seller Guide warns that the
limit "applies independently to each method", so an implementation that sent both a
licence-keyed record and a legacy product-code record for the same hour would bill twice
rather than be refused. We only ever write the new one, which is why there is no
compatibility path in this design.

**AWS names our tenancy decision.** Its three documented strategies are separate tenants
per licence, one unified tenant, or letting the buyer choose. §5.2's rule — always a new
tenant — **is** the first of those. That decision was taken on its own merits before this
section was written, and it happens to be the one AWS describes first; it also means a
buyer who deliberately buys twice gets two workspaces, which is the feature Concurrent
Agreements exists to provide rather than a bug to defend against.

**The pinned gem already carries all of it.** Read out of the API model at 1.107.0 on
22 October, rather than assumed:

```
ResolveCustomer output: [customer_identifier, product_code, customer_aws_account_id,
                         license_arn, metadata]
metadata:               [agreement_id]
UsageRecord:            [timestamp, customer_identifier, dimension, quantity,
                         usage_allocations, customer_aws_account_id, license_arn]
```

No bump is needed, and `Gemfile:211` allows one anyway.

### 3.2 What already exists in the codebase, and what is missing

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

**The column is shown, not only stored.** Decided 21 October, and it is not cosmetic: the
moment two payers share an installation, "who is billing this customer" stops being
answerable from the fact that they are paying. An operator looking at a company that owes
money needs to know which system to open before they can do anything at all, and the only
alternative is inferring it from which column happens to be filled — which is precisely
the inference §4.1 exists to replace.

**The admin shipped in slice 1**, read-only and searchable, on both the company's page and
the companies list. Read-only because the provider follows from a subscription existing: an
operator who could type it could claim a company is billed by a system that has never heard
of it.

**The company's own billing screen did not**, and the reason is worth keeping. Until a
second provider can exist there is exactly one true answer to show every customer, so the
screen would say "billed through Stripe" to everyone and teach nobody anything. It belongs
in the slice that makes the sentence capable of being false.

### 4.2 `Billing::Payer`

A small object resolved from a company, answering the questions that are per-company and
are currently asked of `Deployment`:

As built in slice 1:

```ruby
payer = Billing::Payer.for(company)   # also Company#billing_payer

payer.provider            # "none" | "stripe" | "aws_marketplace"
payer.none?               # …and one predicate per provider
payer.bills?              # is anyone invoiced for this company's capacity
payer.requires_bound?     # must the company carry a limit
payer.minimum_workers     # 1, or 3 for a Marketplace company
```

Two that an earlier draft listed are not there. `owns_capacity?` was to be moved
off `Deployment`; it turned out to have no call sites at all and was deleted
instead. `trial?` stayed inside `Billing::Trial`, which already owns that
question — moving it would have widened slice 1 without making slice 2 smaller.

**`bills?` does not read the column, and that is deliberate.** Being billable and
having a payer attached are different facts: a company that has never paid is
still billable — its minutes go on the ledger row and the adapter reports it as
`unbilled` — so reading `provider != "none"` here would silently drop those
companies out of the metered quantity. The object names the axis; the column
starts deciding things in slice 2.

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
cannot render the app. The CSRF skip is the `Web::OidcSessionsController:14` pattern:
scoped to the one action, on a controller that otherwise keeps the web stack.

**No CORS entry, and an earlier draft was wrong to ask for one.** A CORS rule governs
requests JavaScript makes. This is a top-level form navigation, which CORS does not reach
at all.

**What does reach it is `SameSite`, and it decides the shape of the endpoint.** The session
cookie is `SameSite=Lax`, and Lax withholds a cookie from a cross-site *POST* — so the
request AWS makes carries no session, whoever is signed in on that browser. There is
nothing to read and nothing to sign out.

So it is two actions, and the split is forced rather than tidy:

| | |
|---|---|
| `POST /marketplace/aws/register` | the fulfilment URL. Holds no session. Exchanges the token, writes the licence, and redirects carrying a signed, short-lived token naming it |
| `GET /marketplace/aws/continue` | same-site, on our own origin, where the session exists. Signs the visitor out, then lands them per §5.2 |

The carrier is `generates_token_for :registration` on the licence — the idiom
`CompanyMembership` already uses for invitations — rather than the session, which the POST
cannot write to usefully.

**One repository-specific trap, and it is silent.** `ApplicationController#underscore_params`
puts every incoming parameter key through `String#underscore` before any action runs, and
that turns hyphens into underscores. The controller therefore reads
`x_amzn_marketplace_token`, not the name AWS documents. Spelling it as AWS does resolves
`nil`, registers nobody, and raises nothing.

The token is single-use and short-lived, so the exchange happens on arrival; what is
carried onward is the resolved licence, not the token.

**Staging's own front door is in the way, and only for the POST.** The public
entrypoint there sits behind HTTP basic auth, and the request AWS sends is a
form POST from the *buyer's browser* -- which is why `SameSite` governs its
cookie at all. A password prompt in the middle of that POST leaves whether the
body survives the retry up to the browser, and a lost body is not "try again":
the token is spent, so the buyer has to return to Marketplace for another. So
the two paths above skip the prompt and nothing else does. The buyer meets it
at the next step, where the request is an ordinary GET that a retry costs
nothing, and whoever is testing knows the password. What that opens is bounded:
both actions answer an invalid token with a redirect to the sign-in page, which
is itself behind the prompt, and the POST is rate-limited per IP.

`ResolveCustomer` answers with `LicenseArn`, `CustomerAWSAccountId`, `ProductCode`,
`metadata.agreement_id` — and `CustomerIdentifier`, which §3.1 says is **not populated**
for a product on Concurrent Agreements. Nothing may key off it.

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
  of agreement without the application noticing, recorded in the listing
  repository. The offer identifier arrives free in the SNS
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

**`LicenseArn` is the key**: unique, bound to exactly one company, written once. An earlier
draft said `CustomerIdentifier`, which §3.1 corrects — that field is not populated for this
product, and keying on the AWS account id instead would be worse than wrong, because
Concurrent Agreements let one account hold several live agreements and the account id would
collapse them into one tenant.

The distinction has a visible consequence. Two arrivals from the *same AWS account* with
*different* licences are two purchases and get two workspaces; two arrivals carrying the
*same* licence are the same purchase and must land on the same one. Only the licence tells
those apart.

### 5.4 Registration and subscription arrive in either order

AWS emits agreement-created on its own schedule, and a buyer can subscribe and never finish
registering. That leaves a customer who is being billed and has no account — a state that
has to be **visible to us deliberately**, because otherwise the first report of it is a
complaint.

The opposite happens too, and it decides a line of code: somebody registers before the
agreement is confirmed.

**A Marketplace company is never created `trialing`.** Today `WorkspaceOnboardingForm`
writes `billing_state: "trialing"` for every new company, which is right for a stranger
signing up and wrong here: our allowance is switched off by an attached payer (§10), so a
company that AWS bills has no trial to be in.

**And it does not start able to run.** The temptation is to let them in immediately and eat
the few seconds of unbillable capacity, but AWS says not to, and says why: a `subscribe-fail`
means "payment might have failed even though the buyer has already transitioned from the
AWS Marketplace to the seller's SaaS landing page", and the guidance is explicit — "The
seller should wait for the `subscribe-success` message before allowing consumption of the
product", and "To prevent billing issues, we strongly recommend programmatically waiting
for this notification before launching resources on behalf of your customers."

So the company is created blocked, on a reason of its own, and the agreement-created event
is what releases it. The screen the registering person sees in that window is a product
decision nobody has made; what it must not be is an error, because nothing is wrong.

---

## 6. Data model

```
companies
  billing_provider      string  not null  default "none"   # none | stripe | aws_marketplace

marketplace_licenses
  license_arn           string  not null  unique           # THE key -- one per agreement
  customer_aws_account_id string not null                  # NOT unique: an account may hold several
  agreement_id          string  null                       # ResolveCustomer metadata
  product_code          string  not null
  customer_identifier   string  null                       # not populated on this product; kept for forensics
  company_id            bigint  null, unique when present  # null until registration binds it
  subscription_state    string  not null                   # pending | active | ending | ended
  offer_identifier      string  null                       # from the notification, never asked for
  registered_offer_type string  null                       # x-amzn-marketplace-offer-type as it arrived, or null
  subscribed_at         datetime
  ended_at              datetime
```

The table is named for the licence rather than the customer because that is what a row is.
An earlier draft called it `marketplace_customers` and made the AWS account unique, which
§3.1 shows would have merged two deliberate purchases into one tenant.

**`subscription_state` gates metering, and that is not a nicety.** The Seller Guide is
explicit: "Records that are sent to the AWS Marketplace Metering Service before you receive
the ... notification aren't metered." So capacity offered to a company whose licence is
still `pending` is measured (it happened) and not delivered (AWS would discard it). §5.4's
"registration before the subscription is confirmed" is exactly this window.

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
- map company → `LicenseArn`, skipping companies whose provider is not `aws_marketplace`
  and those whose licence is not yet `active`, counting both as Stripe counts its own;
- put `license_arn` on each usage record and **send no product code** — §3.1: for a product
  on Concurrent Agreements the product code is not accepted, and sending both keyings for
  one hour bills it twice rather than being refused;
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

Here they are not. The call must be signed by the account that owns the listing, while
the application runs in a different one, so the client assumes a role in the seller
account and refreshes it. That is a different client construction and a
new way to fail that has nothing to do with metering: a credential error and a metering
rejection must not be reported as the same thing, because one is ours to fix in minutes
and the other is a listing problem.

The region is explicit, not inherited. The pod's default region is not necessarily the
listing's.

---

## 8. Subscription notifications

**EventBridge, not SNS.** An earlier draft of this document, and the listing
repository's own note, both describe an SQS queue subscribed to the seller
account's SNS topics. That is the old integration, and for this product it is not merely
deprecated but unusable: the Seller Guide states that SNS for SaaS products "are being
replaced with Amazon EventBridge notifications", that SNS "doesn't send the `LicenseArn`
parameter", and that sellers registered after 15 July 2026 cannot use SNS at all.

A notification channel that cannot carry the key we bill on is not a channel we can use,
whether or not our seller account is old enough to be offered it. **This needs the matching
correction in the infrastructure repository:** an EventBridge rule and target, not an
SNS-to-SQS subscription.

**They arrive on the seller account's bus, not on ours.** Read out of the Seller Guide on
22 October: "EventBridge sends events to your default event bus" — the seller account's.
So the rule lives in the seller account while the queue it feeds lives in the one this
application runs in, and
that is a cross-account delivery rather than a routing detail. EventBridge supports an SQS
target in another account **in the same Region**, which us-east-1 is for both, given an
execution role in the rule's account and a resource policy on the queue. Nothing in the
infrastructure repository manages the seller account today, so where that rule is declared
is an open question (§10) rather than a line of Terraform.

The pattern matches `"source": ["aws.agreement-marketplace"]`. Not `aws.marketplace`.

**We are both manufacturer and proposer**, because we extend the offer directly, and the
Seller Guide says that "to avoid redundant messages, only the proposer purchase agreement
event is sent when you are both". So the purchase-agreement events arrive in their
**Proposer** spelling and the licence events in their **Manufacturer** one, and a rule
written against the wrong half of that pair matches nothing at all:

| Event | What it means | What we do |
|---|---|---|
| `Purchase Agreement Created - Proposer` | a new, replaced or renewed agreement | `subscription_state` → `active`; before this AWS discards records (§6) |
| `Purchase Agreement Amended - Proposer` | the agreement changed | re-read and store; the offer identifier moves |
| `Purchase Agreement Ended - Proposer` | expired, cancelled or terminated | block the company. **Not** the metering deadline — see below |
| `License Updated - Manufacturer` | the entitlement changed | store. Nothing to act on under pure usage pricing |
| `License Deprovisioned - Manufacturer` | **the one-hour final reporting window opens** | meter that licence immediately, then `ended` |
| `Spend Threshold Vet Failed` | AWS could not verify the buyer's card | usage-based products only. Nobody has decided what this should do |

**An earlier draft of this section had the deadline on the wrong event**, and the mistake
was expensive in the direction that matters. It said agreement-ended starts the hour. It
does not: "AWS Marketplace sends the License Deprovisioned - Manufacturer event to signal
the start of the final reporting window. Sellers have one hour after receiving this event."
Metering off agreement-ended would fire at a moment AWS has not opened the window at, and
the usage that falls between the two events would be reported at neither.

**The one-hour window does not fit the hourly schedule, and this is the sharpest thing in
this section.** The capacity meter runs at five past the hour (`5 * * * *`) and reports the
hour that has just closed. A licence deprovisioned at 10:10 gives us until about 11:10; the
partial hour 10:00–10:10 would not be offered to AWS until 11:05 at the earliest and, for
any later minute, not until after the window has shut. So that event must meter the licence
there and then rather than waiting for the schedule — a second entry point into
`CapacityMeter`, scoped to one licence and a part-hour, and the only place in this design
where metering is event-driven rather than periodic.

**The licence states belong in `app/state_machines`, and the argument is the
delivery rather than the shape.** SQS neither orders messages nor delivers them
exactly once, so a stale `active` can arrive after `ended` and the same event
can arrive twice. Assigned to a column that is only read, either is applied in
silence -- and this column decides whether an hour is billed, so a silent
regression charges for an hour nobody ran, or drops the last one. A machine
refuses the transition rather than recording it.

It is not written yet because there is nothing to transition: rows are created
`pending` by the column default and nothing moves them until this slice.
`Company` carries both idioms side by side -- `state` through a machine,
`billing_state` assigned -- and the difference between them is exactly whether
anything is allowed to refuse a move.

An agreement created for a licence nobody has registered is §5.4's state, and it needs
somewhere to be seen. The admin panel is the obvious home; what it must not be is a log
line.

**A free trial is not announced; it is asked about.** The created event does not say so —
"DescribeAgreement API is used to determine if the new agreement is a free trial" — which
is a second place the answer lives, beside the registration parameter §5.1 stores. Neither
is load-bearing while §10 says trials change nothing we do.

The offer identifier rides these events and is the only per-deal context that reaches us
anywhere. It is stored (§6) and otherwise ignored.

---

## 8.2 What the first cancellation found, 23 October

All four events arrived and applied, seconds apart:

```
12:36:18  Purchase Agreement Ended - Proposer
12:36:49  License Deprovisioned - Manufacturer
```

and the licence went `ending` then `ended`, the company stopped. The inbound
path is proved in full, licence events included.

**The final meter sent nothing, and the hour was lost.** Thirty-six minutes of
a running workspace went unbilled -- in the one hour AWS gives for exactly
this.

The two events apply in a single drain, in order. `Ended` stopped the company
first; `Deprovisioned` then metered a company that `CapacityWindow` answers for
with nothing -- and answers so **for the whole hour**, including the part it
was running, because the window reads the billing state as it is now rather
than as it was. Measured against the row afterwards: `billed: {}` and
`offered: {}`, while the capacity record (`1` worker since 09:45) and the
session limit were both untouched.

**The same trap was already understood for Stripe.** `Billing::FinalUsage`
opens with "MEASURED BEFORE THE COMPANY IS STOPPED ... a stopped company is
offered nothing and billed for none of it". That path avoids it; this one was
written separately and walked straight in.

Fixed by metering before stopping, in both handlers. `Ended` now meters first,
and `Deprovisioned` still meters -- the second copy comes back
`DuplicateRecord`, which costs nothing, while a missed first copy costs the
hour.

**No test could have caught it.** The deprovisioning test asserted the meter
was called on a `meterable?` licence, and it was. What the test did not know is
that the previous event had already made the company unmeasurable.

---

## 8.1 What the first paying customer proved, 23 October

Metering works end to end. The hour `11:00Z` went as `sent=1` against a real
licence, which is the one link no test could reach: capacity measured, company
matched to its licence, the seller role assumed from production, and
`BatchMeterUsage` accepted by AWS.

**The replay window is not theoretical.** The hour `10:00Z` failed at 12:05 on
a usage record missing the buyer's account id. After the fix shipped, the next
run picked it up out of the ledger and sent it -- `attempts: 1`, `sent=1`,
inside the six hours AWS still accepts. A defect found and fixed the same day
cost no billable hour at all. That is what the window was for, and it had never
been exercised against a real refusal.

**The subscription's status in the buyer console tracks the first usage
record.** It read `Pending` for three hours while metering kept failing, beside
a third-party SaaS subscription in the same account reading `Active`, and
turned `Active` by itself the moment a record landed. Nothing was done to it.
So that label is a downstream signal of metering rather than of the agreement,
which is `ACTIVE` from both sides throughout -- useful to know, because a
seller watching only the console would read a working subscription as broken,
and a broken one as merely slow.

`unbilled=4` in every summary is the four Stripe companies on the same
installation: counted, deliberately not sent.

---

## 8.5 Keep what AWS calls the record

`BatchMeterUsage` answers every accepted record with a `MeteringRecordId`. The
adapter read it and threw it away, so "the hour was billed" rested on our own
reading of a `Success` and the next independent check was the customer's
invoice, hours behind. On 23 October that gap cost an afternoon: two hours were
accepted and nothing outside this application could confirm it.

Kept now. The hourly path writes `{license_arn => MeteringRecordId}` into
`capacity_meter_reports.receipts`; the final meter appends `receipt=` to the
line it records on the event. A replay carries no new id, so it is written as
`duplicate` rather than left blank, which would read like a record that went
missing.

`external_id` still carries our own summary. The distinction is the point:
one is what we believe happened, the other is what the service says.

**Who puts this in the buyer's bill.** Nothing of ours. AWS Marketplace turns
accepted metering records into line items on the buyer's account, which reach
their Cost and Usage Report and, from there, Cost Explorer. The queue in this
design is inbound only -- subscription events -- and has no part in billing.
The lag between an accepted record and a visible charge is that pipeline's,
which is why a receipt held here is worth more than a view of theirs.

---

## 8.4 The final meter answers for itself

The hourly meter leaves a ledger row per hour carrying its state, its attempts
and its error. That is how a refused usage record on 23 October was seen and
fixed inside the hour.

The final meter -- the one that runs on deprovisioning, inside the window AWS
allows and nowhere else -- left nothing at all. When the first cancellation was
tested, whether it had billed the customer's last twenty-seven minutes could
not be answered from this side: the only evidence was the buyer's own invoice,
hours behind. A billing path whose success is unknowable is not finished.

It now answers with a line, and the event that ran it records it:
`sent=1:already=0:minutes=27`, or `refused: <what AWS said>`, or
`nothing to send`. Minutes as well as counts, because the point of this path is
the part-hour the schedule cannot reach and a reader needs to see it was not
zero.

Still deliberately not raised. The caller's next step is to end the licence,
and one left open because its last minutes were refused would go on being
billed by the schedule for an entitlement AWS has already revoked. The refusal
goes in the line instead of into the control flow.

---

## 8.3 The queue is not ours alone

The rule in the seller account matches `source` and `detail-type`. It does not
match a product, and it cannot: a rule filters the bus, and the bus carries
every agreement that account transacts. So this queue receives the agreement
traffic of every listing the seller sells -- other products, other buyers,
other teams.

Seen on 23 October: a stranger's subscription to another vendor's product
(`prod-5xwbgb7premi2`, "Easy Cloud Assurance", buyer `474939504552`) was
recorded here and sat unapplied. It names no licence of ours and never will,
so every sweep would have reconsidered it for ever, and the table would have
grown with the seller account's whole business.

Filtered on arrival instead. The two halves of the stream name the product
differently -- agreement events carry `detail.product.id`, licence events
carry `code` and `id` both -- so the application knows the listing by **both**
identifiers now (`AWS_MARKETPLACE_SAAS_PRODUCT_ID` beside the code). An event
naming no product at all is still kept: better a row nobody matches than a
dropped one that was ours.

**Rows recorded before this are still there** and will not match. They are
harmless beyond the work of reconsidering them, and a one-off delete is all
they need.

---

## 9. Where this is tested

Staging, and it is already shaped for it — `DEPLOYMENT_MODE: saas`,
`REGISTRATION_ENABLED: "true"` and a Stripe test-mode price are all set
in staging's Helm values. So the Marketplace path stands
up beside a live Stripe path there, which is the per-company-payer problem in miniature on
a real environment.

Two things to know before planning the first deploy:

- **The deploy workflow takes any branch of this repository whose CI is green on
  staging** — it is dispatched by hand from the private deploy repository — so a feature
  branch can be exercised there without a release tag.
- **Migrations run before the new code is promoted**, so for the few minutes between them
  the new schema is served by the old code. Every migration here is additive, and the code
  that requires a new column ships in the slice after the one that adds it.

The public door is the constraint, and its shape matters more than its addresses. Staging's
own host resolves publicly but sits behind HTTP basic auth, which AWS cannot pass. A second
host exists for exactly this problem — third parties that must reach staging and cannot
authenticate — and it routes a small, explicit list of path prefixes through a middleware
that rewrites `Host` to the internal name. The Marketplace registration POST needs one more
entry on that list, which is the same change SCIM and the YouTrack pairing API each made
for the same reason. Both hosts and the exact rules are in the infrastructure
repository.

A tester will meet one basic-auth prompt partway through the flow, when the app redirects
from the auth-free host to staging's own. That is expected on staging and not a defect.

On the AWS side this wants a `[TEST]` SaaS product with Limited visibility and an
allowlisted buyer account, pointed at staging — the shape the container product already
proved — rather than the real draft, which carries the real product code and the real
marketing copy.

---

## 10. Open questions

- ~~**The Stripe subscription left behind.**~~ Answered on 25 October, and the shape is
  the one this bullet asked for: a person resolves it, and the application's only job is
  to put the question in front of the right person. See §10.1 below for what was built
  and for the one thing this bullet got wrong.

  The original text is kept because its reasoning is still the reasoning:

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
- **Free trials: one verification, no design.** Settled on 21 October, and the settlement
  is that there is nothing for us to build. Our own allowance is switched off by any
  attached payer, Stripe or AWS alike, and an AWS free trial is AWS's own discount applied
  to the usage we report in the ordinary way. So the two mechanisms never meet: there is no
  state in which `Billing::Trial` and a Marketplace trial are both live for one company.

  That matches what the documentation implies (below) without either of them saying it
  outright, which leaves exactly one thing to do and it is a test rather than a decision —
  see the first bullet below.

  **Does metering during a trial charge the buyer? Strongly implied, never stated.**
  Searched on 21 October. Nothing in the Seller Guide tells a seller to stop metering
  during a trial, and two sentences say the trial is a grant of free usage rather than a
  suspension of reporting: the seller page speaks of "the free usage amount granted during
  a free trial", and the buyer page says the procurement page shows "the duration of the
  free trial period and how much free software usage is included in the trial". Read
  together, AWS discounts and we meter exactly as always.

  That is an inference from two sentences about something else, and it is also what the
  product side expects — the discount is AWS's and arrives on its own. Two independent
  readings agreeing is worth something and is still not AWS saying it, and the mistake it
  guards against charges a customer who was promised nothing.

  **So this is now a test, not a question.** Because nobody is building trial handling,
  the whole of the risk is "AWS does not behave as both of us assume", and that is
  observable: put a free-trial offer on the `[TEST]` listing, subscribe from the allowlisted
  account, let an hour meter, and read the buyer's bill — the same Cost Explorer check the
  container product already uses. A zero there
  settles it in a way no reply would. Worth asking Seller Operations in the same breath, in
  one line: *for a usage-priced SaaS free trial, does the seller keep sending
  `BatchMeterUsage` records, and does AWS zero-rate them for the trial term?*

  Two facts settled along the way: one free trial offer per public SaaS product, length
  7–90 days, and **the dimensions cannot be changed for a subscription free trial** —
  which removes the idea of trialling on a cheaper dimension. And each AWS account may use
  a product's free trial only once.

  **A trial on this product costs us, and the buyer sets the number.** This is the
  consequence nobody has named yet, and it is not an AWS question. On the container
  product a trial runs in the buyer's own account on their own hardware, so capacity costs
  them whatever we charge. Here the workers run on our cluster. Meanwhile
  `Web::Company::SettingsPolicy#manage_capacity?` lets a company admin raise their own
  number — correct for a metered product, where raising it raises the bill, and **not**
  correct during a trial, where it raises nothing but our costs. `MARKETPLACE_MINIMUM_WORKERS`
  is 3; nothing stops a trialling buyer from setting 50 on the first day.

  The discount being AWS's own **sharpens** this rather than settling it. If AWS zero-rates
  what we report, then during a trial the buyer pays nothing and the workers still run on
  our cluster: the cost is entirely ours, and the person deciding how much of it to incur
  is the buyer. Nothing in "AWS applies the discount" puts a ceiling on that.

  So a free trial needs a ceiling the customer cannot raise, for its duration. The
  mechanism already exists and is the one §4.3 says must not reach a Marketplace company:
  `Billing::EffectiveCapacity.ceilings`. If trials happen, that sentence needs refining
  rather than reversing — our queue-hour allowance still must not apply, but the clamp it
  rides on is exactly what a trial wants.

  This is the one part of free trials that is ours to build, and it only becomes due when
  somebody decides to create the offer.

  **How a trial ends: answered, and it needs no work.** The buyer guide is unambiguous —
  "SaaS free trials won't automatically convert into paid agreements. If you no longer want
  the free trial, you can let the free trial expire." So there is no trial-end event to
  consume and no date for us to hold: an expiring trial is an agreement ending, and §8
  already blocks the company on that. A buyer who then buys arrives as a *second* agreement
  created, carrying a new offer identifier — which §5.3 already handles, because it is a
  new licence.

  The one thing this does change is expectation rather than code: a trial that nobody
  converts ends in a blocked company holding real work, and the only thing that brings it
  back is the buyer purchasing. Whatever we say to them at that moment is a product
  decision nobody has made.
- **The reverse: a Marketplace customer who wants to pay by card.** Closed by §1 in one
  direction only — they cannot attach a card while AWS bills them. What they do after
  unsubscribing, when their company is `blocked` and the Checkout refusal is still in
  force, is not written down anywhere. The rule probably wants to be "the refusal is on
  an active Marketplace subscription, not on a company that once had one", but that
  sentence has not been checked against the unsubscribe states in §8.
- ~~**Where the seller account's EventBridge rule is declared.**~~ Answered on 22 October.
  Nothing manages the seller account as code -- the infrastructure repository owns the
  account this runs in and says plainly that nothing in it may depend on the listing
  repository, which owns no infrastructure at all. So the rule, and the two roles beside
  it, are an idempotent script in the listing repository: readable, re-runnable and
  diffable, which a console session is not. The queue, its policy and this application's
  right to read it stayed ordinary work in the infrastructure repository.
- ~~**The exact dimension identifier.**~~ `worker_minute`, decided 22 October. Already the
  adapter's constant. Immutable once the listing is published, so from that moment the two
  can only be changed together by creating a second dimension.
- **Whether this product is on Concurrent Agreements at all.** The whole keying
  argument in §3.1 rests on it, and two measurements on 23 October point the other
  way: `ResolveCustomer` returned a populated `CustomerIdentifier` (`Ea8AMTG8jb1`),
  which this document says the programme stopped sending, and `BatchMeterUsage`
  refused a record keyed on `LicenseArn` alone, asking for a customer key. Neither
  changes what we now send — the account id and the licence ARN work either way —
  but the premise behind "the key is LicenseArn, not CustomerIdentifier" was taken
  from the documentation and has never been confirmed for this listing. Worth
  settling before the keying is relied on for anything else.
- ~~**What a Marketplace workspace is told when it is stopped.**~~ Answered 23 October.
  It was being told it had spent its hundred free worker-hours and should add a card --
  an allowance it was never offered, and a Checkout its payer is refused. The allowance
  banner now withholds itself from a payer AWS bills, and a banner of its own stands
  beside it: *waiting* while AWS has not confirmed the subscription, which says plainly
  that nothing needs doing and offers no action; *ended* when it has lapsed, with a link
  to the buyer's own AWS Marketplace subscriptions. Silent while the workspace runs --
  the subscription is managed in the buyer's account and no number of ours belongs on
  every screen.
- **Where a subscribed-but-unregistered customer is shown**, and who is expected to look.
  **Seen for real on 23 October, on the first subscription.** The buyer's domain already
  had a workspace, so `domain_is_free` refused them with "ask someone there to invite
  you" -- a rule written for self-serve signup, applied to somebody who has already paid.
  The subscription stays bound to nobody and the buyer has no way forward at all. The
  rule itself is right: colleagues from one domain belong in one workspace. What is
  missing is the branch for a paying arrival, and the likely answer is neither a second
  workspace nor a refusal but **binding the licence to the workspace that already holds
  the domain** -- which needs somebody there to accept it, and so needs a screen.
- ~~**One service account or two**~~ for the right to assume the seller role. One: the
  infrastructure applied on 22 October attaches the Marketplace policy to the role the
  web and worker pods already carry, rather than introducing a second service account that
  would take the asset access with it.
- ~~**Whether the registration page may live on the production domain**~~, and what AWS
  requires of it during assessment. Answered 22 October: both, in that order. The
  fulfilment URL is an ordinary change request rather than something frozen at
  publication, so it points at the staging host while the product is Limited and moves to
  the production host **before** public visibility is requested -- because the Seller
  Operations team conduct buyer testing themselves at that point, and would otherwise
  test staging. What they require of the page is still only discoverable by doing it.

## 10.1 How the overlap was resolved, 25 October

The first bullet above asked for the overlap to be surfaced and left to a person. That is
what shipped, with one correction and one addition the bullet did not foresee.

**What the bullet got wrong.** It assumed §5.2 gives an existing Stripe customer a *new,
empty* tenant. It does not, whenever the buyer uses an address at their own domain:
`WorkspaceOnboardingForm#domain_is_free` refuses, because that domain already has a
workspace. So the customer does not end up with two tenants — they end up stuck on a form
that tells them to ask someone there for an invitation, which is advice for a stranger
and the wrong thing to say to somebody who has just paid. The overlap was never invisible;
it was being reported as a validation error.

The new-empty-tenant case survives only where the buyer uses an address at a *different*
domain, and there the overlap remains invisible exactly as the bullet says.

**What a person decides.** The buyer asks the administrators of the workspace at their
domain to apply the subscription; one of them accepts or declines it on the Billing tab.
Three things make that safe, and all three are load-bearing:

- the workspace is never a parameter — it is whichever one holds the asker's own email
  domain, so there is nothing through which to aim a request somewhere else;
- the address is one they proved by opening a link sent to it
  (`MarketplaceProposalTicket`), not one they typed, so a request cannot be raised
  against a domain the asker has no mailbox at;
- an administrator of that workspace still has to agree, through the same Pundit policy
  that guards the Billing tab's own controls.

**The Stripe subscription, which is what the bullet was actually about.** Accepting
cancels it in the same transaction — and *immediately*, not at the period's end. The
bullet's fear was that cancelling sets `billing_state: "blocked"` with reason `canceled`
and clamps the company to a ceiling of `0`. That fear is correct for a cancellation that
leaves nobody paying, and does not apply here: AWS becomes the payer inside the same
transaction, so the stopped state is never reached. Period-end cancellation was
considered and is wrong for this product — capacity is billed in arrears
(`Billing::StripeClient#cancel_subscription`), so there is no paid-for remainder to run
out, and letting it run would bill the same hours to Stripe and to AWS both.

Ordering matters and is fixed: the final usage is measured while the workspace is still
Stripe's to bill, then Stripe is cancelled, then the licence is bound and the payer
switched. `stripe_customer_id` is deliberately kept — the final invoice is settled
through it — and only `stripe_subscription_id` is cleared.

**What this amounts to.** A supported path from Stripe billing to AWS billing for an
existing workspace, keeping its data, its members and its work. Its limits are worth
stating because they are easy to overstate: it works only when the buyer's address is on
the workspace's own domain; only in that direction (the reverse is still the open
question two bullets down); it attaches a purchase that already exists rather than
initiating one; and it does not merge two tenants for a customer who already has them.

It also has a commercial consequence that is not a technical one: it is a self-serve way
for a paying direct customer to move onto Marketplace, where AWS takes its listing fee.
If that is not wanted, the narrowing is small — the acceptor becomes us rather than the
workspace's own administrator, which is one policy.

**Deliberately not built.** A history of declined requests (one licence holds one live
request and a second replaces it; a table buys history nothing needs until somebody
disputes one). Asking a workspace at a *different* domain — that is an invitation code,
a different mechanism of trust. Moving a licence from one workspace to another.

---

## 11. Implementation breakdown

| | Slice | Why here |
|---|---|---|
| 1 | **Built.** `billing_provider` + `Billing::Payer` + the payer shown read-only in the admin, behaviour otherwise unchanged | The riskiest change, because it touches the live Stripe path. Alone and first, so a staging failure is unambiguous. The customer-facing display moved to slice 2, where there is more than one answer to show |
| 2 | The seller-account client, `marketplace_licenses`, the registration endpoint, `ResolveCustomer`, the sign-out-and-create flow, the Checkout refusal, and the duplicate-domain detector from §10 | Needs slice 1's column to bind to. The detector ships here rather than later: after this slice the overlap it finds can exist |
| 3 | `Billing::Meter::AwsMarketplaceSaas` | Independent of 2 — can be proved against a hand-bound licence row. An earlier version of this table put the assumed-role client here; it belongs in slice 2, because `ResolveCustomer` is a call to the same service and must be signed the same way, so the registration endpoint cannot exist without it |
| 4 | Two providers in one run of `CapacityMeter` | Separated from 3 so a metering bug and an orchestration bug cannot be confused |
| 5 | EventBridge consumption, the licence states **as a machine in `app/state_machines`**, and the immediate final meter on `License Deprovisioned - Manufacturer` | Needs the rule and queue, which is infrastructure work. The one-hour window (§8) makes this the slice that decides whether a cancelling customer's last hour is billed at all |
| 6 | The fulfilment URL's route, config, and a live run against the real listing held at **Limited** visibility | The first time any of it meets AWS. Limited means the product is visible only to allowlisted AWS accounts, so we subscribe to our own product from our own account: a real agreement, real events, a real `LicenseArn`, at $0.01 a dimension. An earlier version of this row assumed a second `[TEST]` listing; the allowlist makes one unnecessary |

Slices 1, 3 and 4 are provable in the test suite. Slices 2, 5 and 6 are not finished until
they have run on staging against a real subscription.
