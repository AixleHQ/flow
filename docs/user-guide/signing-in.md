# Signing in & SSO

Flow accepts several ways to prove who you are, and each workspace decides which
of them it will take. Those are two separate questions, and keeping them apart is
what lets one person belong to a relaxed workspace and a strict one at the same
time without being thrown out of either.

## The methods

| Method | Who sets it up | Notes |
| --- | --- | --- |
| **Password** | the person | Always available |
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

## How a workspace decides what it accepts

**Sign-in methods** under Admin lists every method this workspace takes. Turning
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

Admins can point a workspace at their own OIDC provider. **Sign-in methods →
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

A workspace can let an identity provider add and remove its members. **Sign-in
methods → Directory sync** generates a token, shown once, and names the endpoint
to point your directory at.

What it does and does not do:

- Removing someone in your directory removes their access here.
- The token alone decides which workspace a request touches. There is no
  workspace in the URL, so a leaked link reveals nothing and grants nothing.
- Provisioning someone does **not** create a credential. They get an account with
  no way in until their first real sign-in — which is what makes provisioning
  before a first login coherent rather than a second source of truth.

## Your account

**Profile → Security** shows what you hold: your passkeys, whether codes are on,
and every device signed in. A sign-in you do not recognise can be ended from
there.

Signing in with a method your account has never used before does not silently
attach it. If an account already exists for your address, Flow asks you to sign
in the way you usually do and add the new method from inside your session —
because an email address in an assertion is not by itself proof that the person
holding it owns that address.
