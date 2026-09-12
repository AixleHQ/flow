# Azure DevOps app registration — operator runbook

How to give a Flow deployment an identity that can reach Azure DevOps. Written
for the person doing it, in the order they will do it, with the errors they will
actually hit.

Design background: [design/azure-devops-integration.md](../design/azure-devops-integration.md) §5.
The customer-facing half is in [user-guide/integrations.md](../user-guide/integrations.md).

---

## 0. Decide which mode you need

| | **Multi-tenant** | **Single-tenant** | **PAT** |
|---|---|---|---|
| Who can it reach | Organizations in **any** tenant that installs it | Organizations backed by **your own** tenant, and nothing else ever | One organization |
| Acts as | The application | The application | **The token's owner** |
| Use it for | Anything a customer will ever touch | A deployment that will only ever serve its own directory | A smoke test, or an MSA-backed organization |

**Register as multi-tenant unless you are certain the deployment will never serve
another directory.**

Single-tenant is not "the simpler start" — it is a dead end. Another tenant
cannot provision a service principal for a single-tenant application at all:
`az ad sp create` there does not work, and no permission grant fixes it. And it
buys nothing in exchange, because a multi-tenant registration creates its service
principal in the home tenant exactly the same way — so a first test against an
organization in your own directory is identical work either way, and §3 is
skipped either way.

The exposure of multi-tenant is close to nothing. Anyone who knows the client ID
can instantiate the application in their own directory, and that grants them
nothing: the application requests no permissions, and reaching anything requires
*their* Azure DevOps administrator to add it to *their* organization. The worst
someone can do is give our application access to an organization they control —
which is the install.

Already registered as single-tenant? **Authentication → Supported account types**
switches it. The client ID and everything else survive.

**Hard limit:** a service principal can only be added to an Azure DevOps
organization from the Entra tenant that organization is connected to. An
organization still backed by a personal Microsoft account has no such tenant, so
**PAT mode is the only option there** — no amount of app registration will help.
Check first: **Organization settings → Overview**; if it shows no Microsoft Entra
directory, you are in that case.

---

## 1. Register the application (Entra)

Done once per Flow deployment, by whoever owns the deployment.

1. Go to the [Microsoft Entra admin center](https://entra.microsoft.com) →
   **Applications → App registrations → New registration**.
2. **Name:** something an Azure DevOps administrator will recognize in a user
   list — they will be adding it by display name. `Aixle Flow` is fine;
   `aixle-prod-sp-01` will get declined by someone who does not know what it is.
3. **Account types.** The portal currently offers four; two of them are never
   right here, because a personal Microsoft account cannot be a service
   principal in Azure DevOps.
   - **Multiple Entra ID tenants** — this one, per §0.
   - *Single tenant only - `<your directory>`* — only for a deployment that will
     never serve another directory; see §0 before choosing it.
   - *Any Entra ID Tenant + Personal Microsoft accounts* and *Personal accounts
     only* — not these, ever.
4. **Redirect URI:** leave blank, despite the form saying a value is required for
   most authentication scenarios — that note is about browser sign-in flows.
   Client credentials never redirect.
5. Register, then copy from the **Overview** page:
   - **Application (client) ID** → `AZURE_DEVOPS_CLIENT_ID`
   - **Directory (tenant) ID** → the `TENANT_ID` for step 5, if the organization
     is in this same tenant

**Do not add any API permissions.** Azure DevOps does not use Entra application
permissions — it has its own permission system, and access is granted in step 4.
Adding `vso.*` scopes or Graph permissions here does nothing and invites a
reviewer to ask why they are there.

---

## 2. Give it a credential

Same blade, **Certificates & secrets**.

**For a first test — client secret:**

1. **Client secrets → New client secret**, description `flow`, expiry 6 months.
2. Copy the **Value** immediately. It is shown once; the Secret ID is not the
   secret.
3. → `AZURE_DEVOPS_CLIENT_SECRET`

**For production — certificate.** Shorter-lived secrets are still secrets sitting
in an env var; a certificate's private key can live in a secret store and never
be pasted anywhere.

```bash
# One self-signed cert. Upload the .crt, keep the .key.
openssl req -x509 -newkey rsa:2048 -keyout flow-azure.key -out flow-azure.crt \
  -days 365 -nodes -subj "/CN=Aixle Flow"

# The thumbprint Entra will show you, and that Flow needs:
openssl x509 -in flow-azure.crt -noout -fingerprint -sha1 | sed 's/.*=//; s/://g'
```

Upload `flow-azure.crt` under **Certificates → Upload certificate**, then set:

- `AZURE_DEVOPS_PRIVATE_KEY` — the full contents of `flow-azure.key`
- `AZURE_DEVOPS_CERT_THUMBPRINT` — the hex string from the command above

Flow prefers the certificate when both are configured.

---

## 3. Provision the service principal in the customer tenant

**Skip this entire section for single-tenant.** Registering the app already
created its service principal in your own tenant.

For multi-tenant, the customer's Entra administrator (Cloud Application
Administrator or Application Administrator) runs one of these, with the client ID
you published:

```bash
az ad sp create --id <AZURE_DEVOPS_CLIENT_ID>
```

```powershell
Connect-MgGraph -Scopes "Application.ReadWrite.All"
New-MgServicePrincipal -AppId <AZURE_DEVOPS_CLIENT_ID>
```

Nothing is consented to and no permission is granted — this only instantiates the
application in their directory so it can be named in step 4. Until it exists,
Entra answers token requests for that tenant with *"The client application
{appId} is missing a service principal in the tenant {tenantId}"*.

They should confirm it landed: **Entra admin center → Enterprise applications**,
search the app name. Note its **Object ID** from that pane — that is the one the
`ServicePrincipalEntitlements` API takes, and it is *not* the app registration's
object ID.

---

## 4. Publish the client ID

That is the whole operator job. Adding the application to an organization and
recording which projects it may reach are done by the customer, in Flow, in §5 —
there is no rake task, no admin console step and no ticket to you.

Give each customer two things:

- the **Application (client) ID** from §1
- the one-line Entra step: `az ad sp create --id <client id>` — nothing is
  consented to and no permission is granted, it only makes the application
  nameable in their organization

Everything after that they do themselves.

## 5. The customer connects

In **Project → Integrations → Connect → Azure DevOps** they type their
organization name and paste a personal access token from someone who can
administer it (**Member Entitlement Management (read & write)**).

That token, in one request: proves the organization is theirs, adds the
application to it with a Basic access level and Contributor rights on the chosen
project, and is then discarded. It is never stored and the connection runs on the
application's identity afterwards.

Only the first connection to an organization needs one. Colleagues connecting
further projects are not asked, because the binding is the proof.

**Why a token and not just the organization name.** Our application is legitimately
installed in many customers' tenants, so "does the application have access to that
organization" is true for all of them — a project admin in one company naming
another's organization would get a working connection into it. The name is not
proof; the administrator token is.

## Troubleshooting

The distinction that matters: is it the **credential** (yours to fix) or the
**access** (the Azure DevOps administrator's)?

| What you see | Means | Fix |
|---|---|---|
| `AADSTS7000215: Invalid client secret` | Wrong or expired secret | New secret, bump `AZURE_DEVOPS_CREDENTIAL_GENERATION` |
| `AADSTS700027: Client assertion contains an invalid signature` | Thumbprint/key mismatch. The value is the **base64url of the raw SHA-1 bytes**, not the hex — Flow converts it, so check you pasted the hex the portal shows | Re-copy the thumbprint and key as a pair |
| `The client application {appId} is missing a service principal in the tenant` | Step 3 was skipped, or run against the wrong tenant | `az ad sp create --id <client id>` in *that* tenant |
| Connect → *"not valid for organization"* | The personal access token is wrong, expired, or from another organization. Azure answers an invalid token with a redirect to a sign-in page, not a 401 | A fresh token in that organization |
| Connect → *"cannot administer"* | A real token from someone who is not an organization administrator | A token from someone who can add users, with Member Entitlement Management (read & write) |
| *"The Git repository with name or identifier does not exist or you do not have permissions"* | Almost always a **Stakeholder** license, not a missing repository | Raise to Basic |
| Connect → *"cannot read the chosen projects yet"* | Entitlement is not always instant | Try again in a moment; the binding is not recorded until the application can actually read them |
| Connect → *"is not backed by a Microsoft Entra directory"* | The organization is on a personal Microsoft account | Personal-access-token mode; a service principal cannot be used there at all |

## Rotation

1. Add the new secret or certificate alongside the old one in Entra.
2. Update the env var **and** bump `AZURE_DEVOPS_CREDENTIAL_GENERATION`.
3. Restart. Every cached token minted under the old generation stops being served
   immediately — no sweep, no stale-token window.
4. Open a connection's **Test connection**, then delete the old credential in
   Entra.

Project connections keep their ids and their repository attachments throughout.

## Service Hooks (optional)

Only needed for CI gates and event-driven triggers, and the **only** part of this
integration that needs a publicly reachable host — Azure posts inbound. Set
`AZURE_DEVOPS_WEBHOOK_BASE_URL` to a host Azure can reach; subscriptions are then
created automatically when a connection is made, and a failure to create them
never fails the connection, because everything on demand works without them.

Worth knowing: a subscription Azure has put **on probation** exists and delivers
nothing, which from Flow's side looks exactly like nothing having happened.
