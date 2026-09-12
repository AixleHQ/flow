# Azure DevOps app registration — operator runbook

How to give a Flow deployment an identity that can reach Azure DevOps. Written
for the person doing it, in the order they will do it, with the errors they will
actually hit.

Design background: [design/azure-devops-integration.md](../design/azure-devops-integration.md) §5.
The customer-facing half is in [user-guide/integrations.md](../user-guide/integrations.md).

---

## 0. Decide which mode you need

This is the only decision that changes the work, so make it first.

| | **Single-tenant** | **Multi-tenant** | **PAT** |
|---|---|---|---|
| Who can it reach | Azure DevOps organizations backed by **your own** Entra tenant | Organizations in **any** customer tenant that provisions it | One organization |
| Setup effort | ~10 minutes, all in one place | Adds a provisioning step in every customer tenant | ~2 minutes, no Entra work |
| Acts as | The application | The application | **The token's owner** |
| Use it for | A first live test; a single-company deployment | The product: one Flow deployment serving many customers | A smoke test, or an MSA-backed organization |

**For a first run, pick single-tenant.** It skips §3 entirely and is the same
code path — switching the registration to multi-tenant later is one radio button
plus the per-tenant provisioning, and changes nothing in Flow.

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
3. **Supported account types:**
   - single-tenant → *Accounts in this organizational directory only*
   - multi-tenant → *Accounts in any organizational directory (Any Microsoft Entra ID tenant - Multitenant)*
4. **Redirect URI:** leave blank. This is a service-to-service identity; there is
   no browser flow and no callback.
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

## 4. Add it to the Azure DevOps organization

Done by a **Project Collection Administrator** in the organization, once per
organization.

1. `https://dev.azure.com/<org>` → **Organization settings → Users → Add users**.
2. **Users or Service Principals:** type the app's **display name** from step 1.
   The picker resolves service principals by name; it does not take a client ID.
3. **Access level: Basic.** Not Stakeholder — a Stakeholder cannot read
   repositories at all, and the failure reads as a missing repository rather than
   a missing license.
4. **Add to projects:** only the projects Flow should reach.
5. Add.

Service principals are licensed like users, and **multi-organization billing does
not apply to them** — each organization it joins consumes a license there.

### Permissions

Defaults from the project's Contributors group usually suffice. Grant explicitly
if they do not:

| Flow capability | Azure permission |
|---|---|
| `repositories.read` | Repository **Read** |
| `repositories.write` | Repository **Contribute**, **Create branch** |
| `pull_requests.write`, `pull_request_threads.write` | **Contribute to pull requests** |
| `work_items.read` / `.write` | **View**/**Edit work items in this node** on the area paths in scope |
| `builds.read` | **View builds** |
| `pull_requests.complete` | **Contribute** on the target branch, and it must not be blocked by branch policy |

**Do not grant** Project Collection Administrator, "Bypass policies when
completing pull requests", or force-push. Flow never asks for them, and
`pull_requests.complete` deliberately does not bypass policy.

---

## 5. Configure Flow

In the deployment's `.env`:

```bash
AZURE_DEVOPS_CLIENT_ID=<application (client) id>

# One of these two:
AZURE_DEVOPS_CLIENT_SECRET=<secret value>
# or
AZURE_DEVOPS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
AZURE_DEVOPS_CERT_THUMBPRINT=<40 hex chars>

# Bump on every credential rotation — invalidates every cached access token.
AZURE_DEVOPS_CREDENTIAL_GENERATION=v1
```

There is no enable flag: setting a client id and a credential is what turns the
feature on. Restart so `config/settings.yml` is re-evaluated:

```bash
docker compose restart web worker
```

Then record the approval. Access is approved per organization by an operator,
because a successful API call proves the *application* can reach an organization
and proves nothing about whether the Flow company asking owns it.

```bash
# 1. Record the binding
docker compose exec -T web bin/rails azure_devops:approve \
  COMPANY_ID=<flow company id> \
  TENANT_ID=<directory (tenant) id> \
  ORGANIZATION=<the name in dev.azure.com/NAME>

# 2. Prove the application can actually reach it, and list what it sees
docker compose exec -T web bin/rails azure_devops:verify INSTALLATION_ID=<id from step 1>

# 3. Approve the projects this company may use
docker compose exec -T web bin/rails azure_devops:scope \
  INSTALLATION_ID=<id> PROJECT_IDS=<guid>,<guid>
```

`verify` is the moment of truth: it exchanges the credential for a token and asks
Azure for the project list. Its output tells you which of the two halves is
wrong — see the table below.

---

## 6. Connect and check

**Project → Integrations → Connect → Azure DevOps.** Pick the approved
organization, then one of its approved projects, then what agents may do.
Completing pull requests is unticked by default; tick it only if agents should
merge.

Then: **Repositories → Add** with that integration, and run a session. Expect
`/workspace/repo/azure-<id>-<name>`, and `git fetch` to work with no extra step.

---

## Troubleshooting

The distinction that matters: is it the **credential** (yours to fix) or the
**access** (the Azure DevOps administrator's)?

| What you see | Means | Fix |
|---|---|---|
| `AADSTS7000215: Invalid client secret` | Wrong or expired secret | New secret, bump `AZURE_DEVOPS_CREDENTIAL_GENERATION` |
| `AADSTS700027: Client assertion contains an invalid signature` | Thumbprint/key mismatch. The value is the **base64url of the raw SHA-1 bytes**, not the hex — Flow converts it, so check you pasted the hex the portal shows | Re-copy the thumbprint and key as a pair |
| `The client application {appId} is missing a service principal in the tenant` | Step 3 was skipped, or run against the wrong tenant | `az ad sp create --id <client id>` in *that* tenant |
| `verify` → `credential_action_required` | Entra rejected the credential | Step 2 |
| `verify` → `installation_access_denied` | Entra issued a token and Azure DevOps refused. The app authenticated fine; it is simply not in the organization | Step 4 |
| `TF401444` / *sign-in required* | Service principal not added to the organization | Step 4 |
| *"The Git repository with name or identifier does not exist or you do not have permissions"* | Almost always a **Stakeholder** license, not a missing repository | Raise to Basic |
| `verify` lists no projects | The principal is in the organization but has no project access | Step 4, *Add to projects* |
| Connect shows "No approved organization yet" | Step 5 was not run, or for a different company id | `rake azure_devops:list` |

## Rotation

1. Add the new secret or certificate alongside the old one in Entra.
2. Update the env var **and** bump `AZURE_DEVOPS_CREDENTIAL_GENERATION`.
3. Restart. Every cached token minted under the old generation stops being served
   immediately — no sweep, no stale-token window.
4. Verify one connection, then delete the old credential in Entra.

Project connections keep their ids and their repository attachments throughout.

## Service Hooks (optional)

Only needed for CI gates and event-driven triggers, and the **only** part of this
integration that needs a publicly reachable host — Azure posts inbound. Set
`AZURE_DEVOPS_WEBHOOK_BASE_URL` to a host Azure can reach, then:

```bash
docker compose exec -T web bin/rails azure_devops:hooks INTEGRATION_ID=<id>
docker compose exec -T web bin/rails azure_devops:hook_status INTEGRATION_ID=<id>
```

`hook_status` is worth knowing: a subscription Azure has put **on probation**
exists and delivers nothing, which from Flow's side looks exactly like nothing
having happened.
