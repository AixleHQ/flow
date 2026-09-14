# Connecting Azure DevOps

Azure DevOps connects per Flow project: one connection names one Azure
organization and one or more Azure projects inside it. Agents then clone, push,
open and review pull requests, and read and write Azure Boards work items — in
those projects and nowhere else.

There are two deployments, and they differ in exactly one thing: **who owns the
Microsoft Entra application** Flow authenticates as.

| | Aixle SaaS | Self-hosted |
| --- | --- | --- |
| The Entra application | Already registered. Aixle owns it and holds its key | You register your own, once |
| Its credential | Aixle's, never shared | Yours: a certificate you generate |
| One step in **your** Entra directory | Yes — `az ad sp create` | Yes — the same step |
| Connecting inside Flow | Identical | Identical |

Everything below the application is the same on both. If you are on SaaS, skip
to [Step 1](#step-1-let-the-application-exist-in-your-directory).

---

## Self-hosted only: register the application first

Your operator does this once for the whole deployment, not per customer or per
project. The full runbook is
[operations/azure-devops-app-registration.md](../operations/azure-devops-app-registration.md);
the short version:

1. Register a **multi-tenant** application in Entra (Azure portal → App
   registrations → New registration → *Accounts in any organizational
   directory*). Single-tenant is a dead end — other directories cannot
   instantiate it at all.
2. Give it a **certificate**, not a client secret. Upload the `.crt`; keep the
   `.key`.
3. Configure Flow:

   ```bash
   AZURE_DEVOPS_CLIENT_ID=<application (client) id>
   AZURE_DEVOPS_PRIVATE_KEY="<the whole PEM, real newlines>"
   AZURE_DEVOPS_CERT_THUMBPRINT=<SHA-1 from the portal>
   AZURE_DEVOPS_CREDENTIAL_GENERATION=v1
   ```

4. Publish the client id to whoever will connect organizations. It is not a
   secret; it is how they name the application in step 1 below.

Why a certificate: the application is multi-tenant, so one leaked client secret
is every connected organization at once. With a certificate the private key
never leaves your deployment — Entra holds only the public half — and rotation
means adding a new certificate beside the old one rather than a cutover with a
window where nothing works.

The **Connect → Azure DevOps** entry does not appear until this is configured.
There is no separate feature flag: availability is derived from the credential.

---

## Step 1: let the application exist in your directory

Required on both deployments, once per Entra directory.

A multi-tenant application has to be instantiated in each directory that uses
it. Flow's application requests no Microsoft Graph permissions, so there is no
consent screen to click through — which also means nothing creates the service
principal for you.

A directory administrator runs:

```bash
az ad sp create --id <client id>
```

The connect dialog shows the exact command, with this deployment's own client
id already filled in — copy it from there. It is not printed in this guide on
purpose: the id differs between the hosted deployment and every self-hosted one,
and a literal here would send half its readers to create a service principal for
somebody else's application.

This grants nothing and consents to nothing. It makes the application
*nameable* in your directory — without it, the next step fails with
`The client application {appId} is missing a service principal in the tenant`.

## Step 2: create a personal access token

Used once, in one request. It is never stored, never logged, and is not what the
connection runs on afterwards.

In Azure DevOps: **User settings → Personal access tokens → New Token**, scoped
to the organization you are connecting. Then **Show all scopes** — the three you
need are not in the short list:

| Scope | What it is spent on |
| --- | --- |
| **Member Entitlement Management** (read & write) | Proving you administer the organization, and adding Flow's identity to it |
| **Project and team** (read) | Listing the Azure projects to choose from |
| **Security** (manage) | One permission grant, so Flow can manage its own Service Hooks |

The person creating it must be an organization administrator — scopes are a
ceiling, not a grant. A token with all three from someone outside **Project
Collection Administrators** is still refused, and says so.

### Why a token at all

An application token proves that *the application* can reach an organization.
With one multi-tenant application serving many customers, that is legitimately
true for every one of them — so it proves nothing about whether **your** company
may bind **this** organization. Organization names are short and often public,
so knowing one proves nothing either.

The token closes that gap: it calls an endpoint only an organization
administrator can call. What survives the request is the binding it justified,
not the token.

## Step 3: connect

**Project → Integrations → Connect → Azure DevOps.**

1. Type the organization name — the one in `https://dev.azure.com/<organization>`.
   Flow does not list organizations: what is not listed cannot be browsed by a
   project member, and a list would reveal which organizations the deployment
   can already reach.
2. Paste the token and press **Verify organization**.
3. Pick one or more Azure projects.
4. Review **What agents may do** — see below — and press **Connect**.

In that one request Flow proves the organization is yours, adds its identity to
it with a **Basic** access level and Contributor rights on the projects you
picked, grants itself permission to manage its own Service Hooks, and confirms
it can actually read every project you selected before recording anything.

Colleagues connecting further Flow projects against the same organization are
not asked for a token — they choose from the Azure projects this connection
approved.

## Capabilities

The checkboxes are Flow's own operation profile, not Azure's permissions.
Unticking one stops the request being sent at all; Azure independently decides
whether the identity may perform the ones that are sent.

All of them are on by default, including **Complete pull requests**. Merging is
part of the delivery cycle an agent is here to run, and Azure's branch policies
are what actually decide whether a merge may happen — Flow never asks to bypass
one, and refuses to complete a pull request whose source branch moved after the
agent read it.

## Adding Azure projects later

The approved set of Azure projects belongs to the **organization binding**,
which is the company's boundary, not a per-connection preference. Reaching a
project outside it needs a token again, for the same reason the first one was
needed: widening the boundary is the same act as establishing it.

Paste a token on the connect screen and the full list of projects you can
administer is offered, already-approved ones included.

The set selected for a given connection is fixed for that connection's life.
Adding to it later would silently widen what every attached agent can already
reach, and removing from it would strand repositories pointing into a project
the connection no longer covers. Connect again instead.

## What the connection runs as

Operations act as the **application's identity**, not as the person who
connected it. Pull requests and comments are authored by it, and an employee
leaving does not revoke it.

Repositories authenticate through a credential helper that fetches a short-lived
token per git operation, so nothing is written into the checkout or the remote
URL. Ordinary `git fetch` and `git push` work with no extra step.

## Service Hooks

Flow subscribes to build and pull-request events so a CI gate on a board card
closes the moment a build finishes rather than on the next reconciliation sweep.

They are provisioned automatically, using the permission granted in step 3, and
owned by the application — not by the administrator who connected, so their
leaving does not stop the events. If they cannot be created, the connection
still works; gates just resolve on the five-minute recovery sweep instead.

Azure posts these inbound, so it needs a host it can reach. Flow uses the
deployment's own domain. Set `AZURE_DEVOPS_WEBHOOK_BASE_URL` only when that
domain is not reachable from Azure — a tunnel in development. A loopback or
private host provisions nothing at all, deliberately: Azure would accept such a
subscription, report it healthy, and fail every delivery in silence.

## Limits

- **Azure DevOps Services on `dev.azure.com`, Git repositories only.** Azure
  DevOps Server (on-premises), TFVC, Artifacts, Test Plans and Wiki management
  are out of scope.
- An organization backed by a **personal Microsoft account**, with no Entra
  directory behind it, cannot use a service principal at all. Those need the
  optional personal-access-token mode, which acts as the token's owner and
  carries that person's permissions.
- Submodules and Git LFS are untested.

## When something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| `missing a service principal in the tenant` | Step 1 was skipped, or run in the wrong directory | `az ad sp create --id <client id>` in *that* directory |
| *"not valid for organization"* | Wrong, expired, or foreign token. Azure answers a bad token with a redirect to a sign-in page rather than a 401 | A fresh token in that organization |
| *"cannot administer"* | A real token from someone who is not an organization administrator | A token from someone who can add users to it |
| *"cannot list its projects"* | The token has no project scope | Add **Project and team (read)** — it is behind *Show all scopes* |
| *"The Git repository … does not exist or you do not have permissions"* | Almost always a **Stakeholder** license, not a missing repository | Raise the identity to Basic |
| *"cannot read the chosen projects yet"* | Entitlement is not always instant | Try again shortly; nothing is recorded until the application can actually read them |
| CI gates always close about ten minutes late | Service Hooks were never provisioned | **Test connection**, which is the retry path |
