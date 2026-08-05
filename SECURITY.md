# Security Policy

We take the security of Aixle Flow seriously. Thank you for helping keep the
project and its users safe.

Aixle Flow orchestrates AI coding agents: it executes agent and tool workloads in
containers, against connected repositories, using credentials supplied by the
operator. That design means credential handling, tenant isolation, and workload
sandboxing are the areas where a defect has the highest impact, and we treat
reports in those areas with particular care.

## Supported versions

Aixle Flow is pre-1.0 and moves fast. Security fixes are applied to the
**latest released version on the default branch only**. Once we cut tagged
releases (see [`ROADMAP.md`](ROADMAP.md)), this table will list the supported
release lines.

| Version            | Supported |
| ------------------ | :-------: |
| Latest (`develop`) |     ✅     |
| Older / forks      |     ❌     |

## Reporting a vulnerability

**Please do not open a public issue, pull request, or discussion for security
problems.** Public disclosure before a fix puts every user at risk.

Report privately through one of these channels:

1. **GitHub Private Vulnerability Reporting (preferred)** — go to the
   [**Security** tab](https://github.com/AixleHQ/flow/security) of this
   repository and click **"Report a vulnerability"**. This opens a private
   advisory visible only to maintainers.
2. **Email** — `security@aixle.com`.

> **TODO (product):** confirm/create the `security@aixle.com` mailbox, and
> enable *Private Vulnerability Reporting* in
> **Settings → Code security and analysis** so option 1 is live before the repo
> goes public.

Please include, as far as you can:

- a description of the vulnerability and its impact;
- steps to reproduce or a proof of concept;
- affected version / commit and environment;
- any suggested remediation.

## What to expect

> **TODO (product):** confirm the response targets below — these are
> best-practice defaults, not yet an agreed SLA.

- **Acknowledgement** within **3 business days**.
- **Initial assessment** (severity + whether we accept the report) within
  **10 business days**.
- We will keep you informed about progress toward a fix and coordinate a
  disclosure date with you.
- With your permission, we will credit you in the advisory once the fix ships.

## Coordinated disclosure

We follow a coordinated-disclosure model: we ask that you give us a reasonable
window to release a fix before any public disclosure. We will not pursue or
support legal action against researchers who report in good faith and follow
this policy.

## Scope

This policy covers the Aixle Flow codebase in this repository and its supporting
services. Particularly relevant areas:

- **Credential handling** — stored third-party OAuth tokens and agent credentials
  (`OauthCredential`, `AgentCredential`), their encryption at rest, refresh flows,
  and any path that could expose token material in plaintext, logs, or API
  responses.
- **Tenant isolation** — authorization across companies, projects, and
  collaborators; any path that lets one tenant read or act on another's data.
- **Workload sandboxing** — escape from, or privilege escalation out of, the
  containers in which agent sessions, tools, and workflow steps execute, and
  resource-quota bypass.
- **Tool and MCP execution** — untrusted tool definitions or MCP server
  configurations that lead to unintended code execution or credential access
  beyond the intended scope.
- **Webhook ingress** — signature verification and replay handling for received
  webhooks.
- **Authentication** — session handling, OAuth/OmniAuth login and account-linking
  flows.
- **Asset storage** — access control on uploaded and generated assets in object
  storage.

### Trust model, stated plainly

Aixle Flow is designed to run code that AI agents produce, inside the operator's own
infrastructure, with the credentials the operator provides. Agent sessions executing
code is the intended behavior, not a vulnerability. What **is** in scope is a user or
tenant obtaining execution or data access **beyond what the operator granted them** —
for example crossing a tenant boundary, escaping the session container into the host
or cluster, or reading another party's credentials.

Vulnerabilities in third-party dependencies should be reported upstream; if a
dependency issue affects Aixle Flow specifically, let us know so we can pin or patch.
