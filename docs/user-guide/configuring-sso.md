# Configuring sign-in methods

For whoever runs the installation. What a workspace admin does from the UI is in
[Signing in & SSO](/docs/signing-in).

## Availability is derived, not declared

An installation offers a provider when it **holds credentials for it**. There is
no separate switch, and that is the point: a self-hoster must never be handed a
toggle for a provider their instance cannot complete a sign-in with.

```ruby
when :google     then Settings.google_oauth&.client_id.present?
when :microsoft  then Settings.microsoft_oauth&.client_id.present?
when :password, :passkey, :magic_link, :totp then true
```

Password, passkeys, codes and email links need nothing configured — they are the
app's own machinery. Google and Microsoft are OAuth clients you register.

`AUTH_ENABLED_KINDS` narrows that set and can only ever offer **less**: an
installation with no Microsoft credentials never offers Microsoft however the
list is written.

## Google

Register an OAuth client (Web application) and add one authorised redirect URI:

```
https://<your host>/auth/google/callback
```

Then set:

```
GOOGLE_CLIENT_ID=…
GOOGLE_CLIENT_SECRET=…
```

The URI must match exactly. A Web client will not accept "any localhost port" —
each host you run on needs its own entry.

## Microsoft (Entra ID)

Register an application in **your** tenant, not a customer's.

- **Supported account types: accounts in any organizational directory.** A
  single-tenant registration admits only your own directory, and no customer
  could sign in.
- Reply URL: `https://<your host>/auth/microsoft/callback` — the path is
  `microsoft`, because the strategy is registered under that name.
- A **client secret**, not a certificate.

```
MICROSOFT_CLIENT_ID=…
MICROSOFT_CLIENT_SECRET=…
MICROSOFT_TENANT_ID=common
```

`MICROSOFT_TENANT_ID` is the **authority** — which directory's login endpoint to
send people to. Leave it `common`: pinning a multi-tenant registration to its own
directory defeats the registration. Which tenant an assertion may come from is a
separate check, and a deployment-wide provider deliberately accepts any.

Two things worth knowing before customers arrive:

- **Publisher verification.** Without a verified publisher, ordinary users in
  another tenant cannot consent for themselves and every new customer needs an
  administrator for the first sign-in.
- **A Microsoft sign-in never adopts an existing account.** Entra sends no
  `email_verified`, and a tenant administrator can set any address on a user
  without proving they own that domain — on a tenant anyone can create for free.
  So an assertion is never evidence that the person controls the address it
  carries. It can create an account under the usual domain rules; attaching
  Microsoft to an account that already exists is an explicit act from a session
  that is already authenticated.

Google is treated differently because Google Workspace does assert
`email_verified`, and that claim is worth something.

## Per-company OIDC needs nothing here

A workspace's own connection carries its issuer and client credentials on its own
row, encrypted. No environment variable, no restart, no deployment — an admin
adds it from the UI. The one thing the installation provides is the callback:

```
https://<your host>/auth/oidc/callback
```

One URL for every connection on the installation.

## The address that matters

Every emailed link and every OAuth callback is built from `DOMAIN` and
`PROTOCOL` — the address a **browser** reaches the app at, which is not always
the port the process listens on. Behind a proxy or a port mapping they differ,
and getting this wrong sends sign-in links to a port the recipient cannot open.

## The claim that identifies a person

Identity is the pair `(provider, subject)` — never an email address. The subject
is binding per provider: `sub` for OpenID Connect, `oid` for Entra, never a UPN
or a mail attribute. Addresses get reassigned when people leave; a subject does
not.

An address may promote an assertion onto an existing account only when the
provider asserts `email_verified` **present and true**, and only when a
company-scoped provider carries a domain that workspace owns. A missing claim is
not a true claim.

## Reference

Every variable, with its default, is in the
[configuration reference](/docs/config-schema).
