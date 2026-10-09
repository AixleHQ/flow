# Signing in & SSO

Flow accepts several ways to prove who you are, and each workspace decides which
of them it will take. Those are two separate questions, and keeping them apart is
what lets one person belong to a relaxed workspace and a strict one at the same
time without being thrown out of either.

## The methods

| Method | Who sets it up | Notes |
| --- | --- | --- |
| **Password** | the person | Set, changed or reset by the person — see [Your password](#your-password) |
| **Google** | the operator, once per installation | One OAuth client for everyone |
| **Microsoft** | the operator, once per installation | Entra ID work/school accounts |
| **Your own OpenID Connect** | a workspace admin | Okta, Entra, Ping, OneLogin, JumpCloud, Google Workspace — anything that speaks OIDC |
| **Passkey** | the person | Lives on their device, works everywhere they belong |
| **Authentication codes** | the person | Six-digit codes from an authenticator app. Confirms an identity, never starts a session |
| **Email sign-in link** | the person | Single-use, short-lived |

A method you cannot see is a method this installation has no credentials for.
Availability is **derived** from configuration rather than declared, so a
self-hosted operator is never offered a switch for a provider their instance
cannot actually complete a sign-in with.

## Which workspace you land in

There is no workspace picker before you sign in. Flow works out where you belong
from the **domain of your email address**: each workspace claims one, and that
claim is unique.

If no workspace claims your domain, you are told so plainly instead of being
given an account that belongs nowhere.

If a workspace does claim your domain but signing in did not add you to it, you
are told how to get in, not handed a form for a second workspace that could only
be refused. Two ways work: sign in with a method that adds people from your
domain (Google, Microsoft or the workspace's own connection, whichever it
accepts), or ask one of its administrators to invite you. A password, a passkey
or an email sign-in link only lets in people who are already members. Until the
workspace has proved the domain, the screen does not name it, and an invitation
is the only way in.

## How a workspace decides what it accepts

**Settings → Access** lists every method this workspace takes. Turning
one off never deletes anyone's credential — a passkey belongs to the person, not
to you — it only stops that method letting someone **into this workspace**.

Two guards make the screen safe to use:

- **Nobody can be stranded.** A change that would leave any active member with no
  usable method is refused, and it names how many people it would have stripped.
  The check covers every member, not just you, so one admin cannot quietly lock
  the rest out.
- **You cannot lock yourself out either.** An edit that would leave your own
  session unable to re-enter is refused as well.

## Connecting your own identity provider

Admins can point a workspace at their own OIDC provider. **Settings → Access →
Connect your own identity provider** wants four things:

| Field | Where it comes from |
| --- | --- |
| Display name | Yours — what members will see |
| Issuer URL | Your provider. Flow reads its `/.well-known/openid-configuration` |
| Client ID | The application you register with your provider |
| Client secret | The same application. Stored encrypted; never shown again |

Register Flow with your provider first. It needs one reply URL:

```
https://<your Flow host>/auth/oidc/callback
```

**One callback serves every connection**, not one per provider — which
connection a sign-in belongs to travels in a signed, single-use `state`, never in
the URL. Adding a second or a tenth connection needs no new URL.

### Verify before you enable

A new connection arrives **switched off**, badged *Not verified yet*, with its
switch held shut. Press **Verify**: Flow sends you through the connection exactly
as a member would go, and only a sign-in that actually completed unlocks the
switch.

This is deliberate. A typo in an issuer or a secret that was pasted with a
trailing space is a connection that cannot admit anyone — and if it could be
switched on unproved, a workspace could be made unenterable by a single careless
save. Verifying is not a way in: while the connection is off, the workspace still
refuses it.

### How members then use it

There is no button per provider on the sign-in screen, on purpose: one screen
serves every workspace on the installation, and a row of customer names would
tell any visitor who your customers are.

Members press **Sign in with your company SSO** and give their address. The
domain resolves to the workspace, and its connection starts. A workspace with
several connections shows a choice rather than guessing; a domain with none says
so instead of failing obscurely.

## Being asked to confirm

Flow checks a workspace's rules when you **enter that workspace**, not when you
sign in, and re-checks them on every request.

So a session that proved one method and crosses into a workspace that does not
accept it is **not signed out** — it is asked to add a proof. Confirm with
something that workspace does take and you continue where you were going.

Proofs **accumulate**. Proving a second method never discards the first, which is
what lets one session satisfy two workspaces with completely different rules at
the same time instead of bouncing you between them.

An administrator who turns a method off ends its proofs immediately: the next
request re-reads the live rules, so revocation does not wait for anything to
expire.

## What each method proves

**Passkeys** are yours, not the workspace's. One is registered against your
device from **Profile → Security**, works in every workspace you belong to, and
only you can add or remove one. A workspace can decline to accept a passkey; it
can never delete one.

**Authentication codes** confirm that you still hold your device. They cannot
*start* a session — there is nobody to look up from a six-digit number — so they
appear when a workspace asks you to confirm, not on the sign-in screen. Set them
up in **Profile → Security**: scan the QR with any authenticator app, or type the
secret if the app has no camera, then enter one code to switch them on. A secret
that was generated but never confirmed does nothing.

**Email sign-in links** are single use and expire in minutes. Opening one lands
on a confirmation rather than signing you in outright, because mail providers
follow links before you do.

## Directory sync (SCIM)

A workspace can let an identity provider add and remove its members. **Settings
→ Access → Directory sync** generates a token, shown once, and names the endpoint
to point your directory at.

What it does and does not do:

- Removing someone in your directory removes their access here.
- The token alone decides which workspace a request touches. There is no
  workspace in the URL, so a leaked link reveals nothing and grants nothing.
- Provisioning someone does **not** create a credential. They get an account with
  no way in until their first real sign-in — which is what makes provisioning
  before a first login coherent rather than a second source of truth.

## Your account

**Profile → Security** shows what you hold: the methods you sign in with, your
passkeys, whether codes are on, and every device signed in. A sign-in you do not
recognise can be ended from there.

### Your password

A workspace admin who was onboarded with Google, Microsoft or an email link has
no password. **Profile → Security → Password → Set password** adds one: type it
twice, no current password needed — you are already signed in. From then on
**Password** appears under *Sign-in methods*, and a Google or Microsoft link that
was your only way in can be removed.

With a password set, the same card offers **Change password**, which asks for the
current one. Passwords need at least 8 characters.

Forgot it? **Forgot password?** on the sign-in screen — or **Forgot your current
password?** in the change form — emails a link to choose a new one. The link
works once and expires after an hour, and the screen says the same thing whether
or not the address has an account. Opening the link only shows the form;
nothing is spent until you save, so a mail scanner that follows links cannot use
it up.

Every set, change or reset:

- emails you, so a change you did not make does not go unnoticed;
- signs you out on every other device — the browser you made the change in stays
  signed in — and turns off your personal MCP token;
- is written to the audit log.

The card offers nothing to set when none of your workspaces accepts a password,
and no reset link is sent for such an account. An administrator acting as you
cannot set or change your password.

### Linking a method

Signing in with a method your account has never used before does not silently
attach it. If an account already exists for your address, Flow asks you to sign
in the way you usually do and link the new method from **Profile → Security →
Sign-in methods** — because an email address in an assertion is not by itself
proof that the person holding it owns that address. Microsoft is the usual case:
it never asserts that an address is verified, so a Microsoft sign-in can create
an account but never take over one that exists.

Press **Link Google** or **Link Microsoft** and sign in to that account at the
provider. It is added to the account you are signed in to, matched by the
provider's own identifier for you, so its address does not have to match yours.
Only the providers this installation offers and one of your workspaces accepts
are listed.

- An account at the provider that is already linked to someone else here stays
  theirs. Linking it to yours is refused.
- The link has to finish in the session that started it. If you were signed out
  while you were away at the provider, nothing is linked: sign in and start
  again.
- There is no separate password prompt. The page is behind the same check as
  every other: a session that does not satisfy your workspace is asked to
  confirm first.

### Removing a method

Google, Microsoft and a workspace's own connection can be removed. A password, a
passkey and an email sign-in link are not removed from this list — they come
back the next time you use them; a passkey is removed under **Passkeys**.

Removing is refused when it would leave you with no way in that one of your
workspaces accepts, or with no way in at all. The page says so, and names the
workspace, before you press anything. An administrator acting as you can neither
link nor remove a method.
