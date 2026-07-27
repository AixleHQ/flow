---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'AWS Bedrock agentic CLI integration for the Aixle platform'
research_goals: 'Compare Bedrock-capable agentic CLIs (Claude Code on Bedrock, Kiro CLI, OpenCode, Crush, Goose, aider, LiteLLM gateway pattern); evaluate both billing models (BYO customer AWS account vs platform-owned account with resale); identify what makes Bedrock consumption count toward AWS partnership tracks (ISV Accelerate, Marketplace, credits); recommend an integration path that maximizes Bedrock token consumption through the platform.'
user_name: 'Artem_petrov'
date: '2026-07-24'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-07-24
**Author:** Artem_petrov
**Research Type:** technical

---

## Research Overview

This research answers a business question: how should the Aixle platform route its users' coding-agent token spend onto AWS Bedrock so that the consumption is real, attributable, and valuable to an AWS partnership? It was conducted 2026-07-24 through the six-step BMAD technical-research workflow, using ten parallel web-research agents against live primary sources (Anthropic, AWS, Kiro, OSS CLI docs and issue trackers) plus direct inspection of the platform codebase, with confidence levels attached to every non-trivial claim.

Scope covered the full Bedrock-capable agentic-CLI landscape (Claude Code, Kiro CLI, OpenCode, Goose, Crush, aider, Codex CLI, Gemini CLI, Cline), both billing architectures (BYO customer AWS account and platform-account resale), the wire-protocol and credential-provisioning mechanics, Kiro-style self-serve auth flows for AWS/Vertex/Azure, and the AWS partner-program economics that determine which architecture Amazon actually rewards.

Headline conclusions: Kiro CLI is commercially incompatible with the goal (subscription-billed, no BYO-Bedrock, embedding prohibited); Claude Code on Bedrock is the sanctioned and strongest vehicle, with OpenCode as the OSS second; and the partnership-optimal architecture is a hybrid — BYO Bedrock consumption registered as AWS co-sell pipeline plus a transactable Marketplace listing for the platform fee, with token resale as a later demand-gated tier. The full executive summary, recommendations, and open verification items are in the **Research Synthesis** section at the end of this document.

---

## Technical Research Scope Confirmation

**Research Topic:** AWS Bedrock agentic CLI integration for the Aixle platform
**Research Goals:**

1. Compare Bedrock-capable agentic CLIs: Claude Code on Bedrock, Kiro CLI, OpenCode, Crush, Goose, aider, and the LiteLLM gateway pattern.
2. Evaluate both billing models: BYO customer AWS account vs platform-owned account with token resale.
3. Identify what makes Bedrock consumption count toward AWS partnership tracks (ISV Accelerate, Marketplace, credits).
4. Recommend an integration path that maximizes Bedrock token consumption through the platform.

**Technical Research Scope:**

- Architecture Analysis - how each CLI connects to Bedrock (env vars, IAM, cross-region inference profiles); fit with the platform's session → Coder workspace → CLI architecture
- Implementation Approaches - agent configuration on Bedrock, per-user/per-session AWS credential provisioning, secrets management
- Technology Stack - CLI versions, licenses, supported Bedrock models, constraints (which CLIs genuinely bill through Bedrock vs separate subscriptions)
- Integration Patterns - IAM patterns (STS assume-role, access keys), LiteLLM/gateway layer, per-user usage accounting for platform billing
- Performance & Partnership Considerations - Bedrock quotas/limits, latency, cross-region inference; AWS partnership criteria and consumption attribution

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-07-24

---

## Technology Stack Analysis

### AWS Bedrock Platform Surfaces

Bedrock in mid-2026 is no longer a single API — three distinct surfaces matter for agentic CLI traffic:

1. **Classic runtime endpoint** (`bedrock-runtime.{region}.amazonaws.com`) — InvokeModel/Converse APIs, cross-region inference (CRIS) profiles with geo prefixes (`us.`, `eu.`, `jp.`, `apac.`, `global.`), Guardrails, Provisioned Throughput. Newer Claude models require inference-profile IDs — bare foundation-model IDs return HTTP 400 ("on-demand throughput isn't supported").
2. **Mantle endpoint** (`bedrock-mantle.{region}.api.aws`) — the new-generation surface: OpenAI-compatible Chat Completions + Responses APIs **and a native Anthropic Messages API** at `/anthropic/v1/messages`. Same per-token pricing as runtime, separate quota pools, SSE streaming, bearer-token auth works as a plain `x-api-key`. AWS recommends it for new applications.
   _Source: https://docs.aws.amazon.com/bedrock/latest/userguide/endpoints.html_
3. **Claude Platform on AWS** (`aws-external-anthropic.{region}.api.aws`) — Anthropic-operated API billed through **AWS Marketplace** (not Bedrock consumption); same-day model parity with the Anthropic API, restores features Bedrock lacks (e.g. server-side web search). Relevant as a contrast option: it keeps spend on the AWS bill but it is *not* Bedrock usage.
   _Source: https://platform.claude.com/docs/en/build-with-claude/claude-platform-on-aws_

**Claude model catalog on Bedrock (July 2026):** Claude 5.x (Fable 5 — GA on Bedrock since 2026-06-09, Sonnet 5, Mythos 5), Claude 4.x (Opus 4.8/4.7/4.6, Sonnet 4.6/4.5, Haiku 4.5, Opus 4.5), plus legacy 3.x at a 2x "extended access" surcharge. New-generation models use suffix-less IDs (`anthropic.claude-opus-4-8`, `us.anthropic.claude-opus-4-8` for CRIS). The non-Claude catalog is broad (OpenAI GPT-5.x, DeepSeek V3.2, Qwen3 Coder, Kimi K2.5, GLM 5, Mistral Devstral 2, Amazon Nova 2, Grok 4.3) — relevant if the platform wants a multi-model story on one billing rail.
_Sources: https://docs.aws.amazon.com/bedrock/latest/userguide/model-cards.html, https://platform.claude.com/docs/en/build-with-claude/claude-in-amazon-bedrock_

**Pricing:** Claude on-demand list prices on Bedrock **match Anthropic direct** (Haiku 4.5 $1/$5, Sonnet 4.6 $3/$15, Opus 4.8 $5/$25, Fable 5 $10/$50 per 1M in/out; Sonnet 5 promo $2/$10 through 2026-08-31). Global routing has no premium; single-geography (regional CRIS) costs +10%. Prompt caching: reads ≈ 0.1x input, writes 1.25x (5-min TTL) / 2x (1-hour TTL). Batch inference −50% (runtime endpoint only). Bedrock spend is ordinary AWS billing — it draws down customer EDP/PPA commitments and can be paid with AWS credits.
_Sources: https://aws.amazon.com/bedrock/pricing/, https://www.cloudzero.com/blog/amazon-bedrock-pricing/_

### Agentic CLI Landscape — Bedrock Support Matrix

| Tool | Claude via Bedrock | Auth = AWS chain | Prompt caching on Bedrock | Headless/automation | License | Fit for "spend lands on Bedrock" |
|---|---|---|---|---|---|---|
| **Claude Code** | Yes — first-class (`CLAUDE_CODE_USE_BEDROCK=1`, Mantle via `CLAUDE_CODE_USE_MANTLE=1`) | Yes (full chain + `AWS_BEARER_TOKEN_BEDROCK`) | Yes, on by default; 1h TTL opt-in | `-p` mode, Agent SDK, GH Actions | Proprietary, but Bedrock-backed provisioning is the officially sanctioned pattern | **Strongest — incumbent in the platform** |
| **OpenCode** (anomalyco/opencode) | Yes — first-class provider | Yes (+ bearer) | Yes (5m TTL only; 1h is open FR #23106; 10x-cost caching bug fixed 2026-02) | `run --format json`, `serve` HTTP API | MIT | **Strong second** |
| **Goose** (aaif-goose, Linux Foundation) | Yes — first-class provider | Yes (+ bearer; env-only setup) | Yes — auto-enabled for Claude on Bedrock | `goose run`, recipes, `GOOSE_MODE=auto` | Apache-2.0 | **Strong** |
| **Crush** (charmbracelet) | Yes (Claude-only on Bedrock) | Yes (+ bearer) | **Disabled by design** — major cost penalty for agentic loops | `crush run -q` (no JSON, no server mode) | FSL-1.1-MIT (competing-use clause — legal review needed) | Risky (cost + license) |
| **aider** | Via LiteLLM lib (`bedrock/` prefix) | Yes (boto3) | Undocumented/unverified; LiteLLM Bedrock-caching bugs open | `--message --yes` | Apache-2.0 | Works but stagnant (no release since 2025-08); not agentic (no MCP/tools) |
| **Kiro CLI** (ex Amazon Q Developer CLI) | **No — no BYO-Bedrock at all** | n/a | n/a | Yes (`--no-interactive`, `KIRO_API_KEY`) | Closed-source | **Disqualified** (see below) |
| **Codex CLI** | Bedrock Mantle supported but **GPT models only, no Claude** | Yes | Yes (GPT models) | `codex exec` | Apache-2.0 | Wrong model family |
| **Gemini CLI** | Proxy-only (LiteLLM shim) | n/a | Depends on proxy | `-p` | Apache-2.0 | Not viable natively |
| **Cline CLI** | In flux — 2026 CLI auth bugs (#6958, #10745, #10770) | Partial | Unverified | Yes, JSON output | Apache-2.0 | Watch list |

_Sources: per-tool sections below._

### Claude Code on Amazon Bedrock (incumbent deep dive)

- **Config:** `CLAUDE_CODE_USE_BEDROCK=1` + `AWS_REGION`; model pinning via `ANTHROPIC_MODEL` / `ANTHROPIC_DEFAULT_OPUS_MODEL` / `ANTHROPIC_DEFAULT_SONNET_MODEL` / `ANTHROPIC_DEFAULT_HAIKU_MODEL` (accepts inference-profile IDs or application-inference-profile ARNs). Defaults since v2.1.207: primary `us.anthropic.claude-opus-4-8` — unpinned deployments silently upgraded to Opus billing rates; pinning is mandatory hygiene for a platform. All of it can be provisioned via the `env` block of `settings.json` — ideal for headless workspace provisioning. _Source: https://code.claude.com/docs/en/amazon-bedrock_ (Confidence: High)
- **Auth:** full AWS credential chain (access keys, STS, SSO, IMDS, `credential_process`), `AWS_BEARER_TOKEN_BEDROCK` (Bedrock API keys), plus `awsAuthRefresh`/`awsCredentialExport` hooks for credential rotation — purpose-built for per-session credential injection. Minimum IAM: `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`, `bedrock:ListInferenceProfiles`, `bedrock:GetInferenceProfile`. One-time per-AWS-account prerequisite: Anthropic use-case form (one `bedrock:PutUseCaseForModelAccess` call covers a whole AWS Organization). _Source: https://code.claude.com/docs/en/amazon-bedrock_ (Confidence: High)
- **Mantle mode:** `CLAUDE_CODE_USE_MANTLE=1` routes to the native Messages API shape on `bedrock-mantle`; newest models (Fable 5, Sonnet 5) live there. Gateway escape hatches for both paths: `ANTHROPIC_BEDROCK_BASE_URL`/`ANTHROPIC_BEDROCK_MANTLE_BASE_URL` + skip-auth flags. _Source: https://code.claude.com/docs/en/amazon-bedrock_ (Confidence: High)
- **Feature deltas vs Anthropic API:** WebSearch tool unavailable on Bedrock; all subscription-tier features (web/mobile/Slack, Routines, Fast mode, analytics dashboard) unavailable; `/usage` shows local estimates only; error telemetry to Anthropic off by default. 1M context available (Sonnet 5 always; `[1m]` suffix for Opus 4.6+/4.8, Sonnet 4.6). Prompt caching on by default. GitHub Actions/GitLab CI work. _Source: https://code.claude.com/docs/en/feature-availability_ (Confidence: High)
- **Licensing — the decisive fact:** Anthropic's commercial docs explicitly bless this pattern: developers building products/services "should use API key authentication through Claude Console **or a supported cloud provider**"; routing through Free/Pro/Max subscription credentials on behalf of users is prohibited. Claude Code + customer/platform Bedrock billing is therefore the sanctioned architecture — and the only Anthropic-approved way to embed Claude Code in a SaaS. _Source: https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use_ (Confidence: High)
- **Cost telemetry:** OTel metrics (`claude_code.token.usage`, `claude_code.cost.usage` with per-model attrs; custom `OTEL_RESOURCE_ATTRIBUTES` for per-user tagging). AWS-native attribution: application inference profiles + cost-allocation tags; since 2026-04-09, Bedrock cost allocation **by IAM principal** in CUR 2.0. AWS publishes a reference implementation ("Guidance for Claude Code with Amazon Bedrock": OTel collector, per-user dashboards, OIDC→STS auth). _Sources: https://code.claude.com/docs/en/monitoring-usage, https://aws.amazon.com/about-aws/whats-new/2026/04/bedrock-iam-cost-allocation, https://github.com/aws-solutions-library-samples/guidance-for-claude-code-with-amazon-bedrock_ (Confidence: High)

### Kiro CLI — Disqualification Analysis

Kiro CLI (Amazon Q Developer CLI auto-migrated to Kiro CLI on 2025-11-24; Q Developer sunsets 2027-04-30) **cannot route inference through a customer's Bedrock**:

- Fixed Kiro-hosted model catalog priced in credit multipliers; no provider endpoints, no API keys, no Bedrock config. BYO-Bedrock is an **open, unanswered feature request** (kirodotdev/Kiro#34). _Sources: https://kiro.dev/docs/cli/models/, https://github.com/kirodotdev/Kiro/issues/34_ (Confidence: High)
- Billing: individuals pay kiro.dev by credit card (never touches AWS); enterprise (IAM Identity Center) subscriptions land on the AWS bill under service **"Kiro"** — AWS revenue, but **not Bedrock consumption**. Internally Kiro runs on AWS's own Bedrock accounts (AWS Service Terms §1.24) with zero attribution to the customer. _Sources: https://kiro.dev/docs/cli/enterprise/billing/, https://aws.amazon.com/service-terms/_ (Confidence: High)
- Embedding blocked: subscriptions are per-individual; ToS prohibits "use with OpenClaw and similar tools that leverage third-party harnesses" — exactly the platform-embeds-CLI pattern. Closed-source since the rebrand. _Sources: https://kiro.dev/faq/, https://github.com/aws/amazon-q-developer-cli_ (Confidence: High)

Verdict: architecturally and commercially incompatible with the business goal. (Confidence: High)

### Open-Source Multi-Provider CLIs

- **OpenCode** (anomalyco/opencode, MIT, 189k stars, releases every 1–2 days): first-class `amazon-bedrock` provider via Models.dev/Vercel AI SDK; auth priority `AWS_BEARER_TOKEN_BEDROCK` → full AWS chain; VPC endpoints and application-inference-profile ARN overrides supported; `opencode run --format json` and `opencode serve` (HTTP API) for automation. Caching on Bedrock works (5m TTL only; a 10x-cost caching bug was fixed 2026-02; proxy setups break caching — #25984). AWS publishes its own integration sample (aws-samples/sample-opencode-with-bedrock). _Sources: https://opencode.ai/docs/providers/, https://github.com/anomalyco/opencode/issues/11662, https://github.com/aws-samples/sample-opencode-with-bedrock_ (Confidence: High)
- **Goose** (Linux Foundation AAIF, Apache-2.0, 51.6k stars, Rust): built-in `bedrock` provider (credential or bearer auth, env-only setup); prompt caching auto-enabled for Claude on Bedrock; strong headless story (`goose run --recipe`, `GOOSE_MAX_TURNS`, CI patterns); MCP-native. Watch: STS-credential refresh issue in long sessions (#5132). _Sources: https://goose-docs.ai/docs/getting-started/providers/, https://goose-docs.ai/docs/tutorials/headless-goose/_ (Confidence: High)
- **Crush** (Charm, FSL-1.1-MIT): Bedrock works via AWS chain but **"Anthropic models through Bedrock, with caching disabled"** (README) — a structural cost penalty for agentic loops; FSL "competing use" clause is a legal risk for a commercial agent platform. _Source: https://github.com/charmbracelet/crush_ (Confidence: High)
- **aider** (Apache-2.0): Bedrock via embedded LiteLLM; last release 2025-08 (~11 months stale), no MCP/agentic loop; Bedrock caching unverified. Legacy option only. _Source: https://aider.chat/docs/llms/bedrock.html_ (Confidence: Medium)
- **Codex CLI**: native Bedrock Mantle support since v0.124.0 — but official doc states "No Claude models are supported" (Responses API only). Relevant only for a multi-model story with GPT-5.x on Bedrock. _Source: https://learn.chatgpt.com/docs/amazon-bedrock_ (Confidence: High)
- **Strands Agents / AgentCore CLI** (AWS OSS): agent SDK + lifecycle tooling, Bedrock-native — building blocks, not end-user coding CLIs. _Source: https://strandsagents.com/_ (Confidence: Medium)

### Gateway and Access-Layer Technologies

- **Bedrock API keys** (GA since 2025-07): short-term (≤12h, inherit generating principal's permissions, production-recommended, programmatic via `aws-bedrock-token-generator`) and long-term (IAM-user-backed, `create-service-specific-credential`, lifecycle APIs, governable via `bedrock:CallWithBearerToken` / `bedrock:bearerTokenType` IAM conditions). Auto-detected via `AWS_BEARER_TOKEN_BEDROCK` by boto3, AWS SDKs, Anthropic SDKs, Claude Code, LiteLLM, OpenCode, Goose, Crush. This is the key primitive for per-session credential injection into workspaces. _Source: https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys.html_ (Confidence: High)
- **LiteLLM proxy** — the dominant OSS gateway pattern: exposes Anthropic-format `/v1/messages` routing to `bedrock/*` models (Claude Code points at it via `ANTHROPIC_BASE_URL` + virtual key); Bedrock auth via static keys, `aws_profile_name`, STS AssumeRole (`aws_role_name`), IRSA, or bearer tokens; virtual keys with `max_budget`, `tpm_limit`/`rpm_limit`, expiry, per-key model allowlists; automatic USD spend tracking per key/user/team. The standard mechanism for metered multi-user Bedrock access. _Sources: https://docs.litellm.ai/docs/anthropic_unified/, https://docs.litellm.ai/docs/providers/bedrock, https://docs.litellm.ai/docs/proxy/virtual_keys_ (Confidence: High)
- **Native alternatives shrinking the gateway's job:** Bedrock's own OpenAI-compatible endpoints (runtime `/openai/v1` + Mantle) and the Mantle Anthropic-native Messages API mean format translation is no longer needed; what remains for a gateway is credential indirection, budgets/metering, and multi-provider routing. Bedrock-native attribution primitives: application inference profiles (+cost-allocation tags), IAM-principal cost allocation (2026-04), Mantle **Workspaces** (Anthropic-compatible per-app isolation) and **Projects** (OpenAI-compatible). AWS Budgets alerts but does not hard-block requests — hard per-user cutoffs still require a gateway. _Sources: https://docs.aws.amazon.com/bedrock/latest/userguide/endpoints.html, https://github.com/aws-samples/bedrock-access-gateway_ (Confidence: High)

### Technology Adoption Trends

- **Convergence on Bedrock as the enterprise billing rail for Claude agents:** Anthropic ships and documents Bedrock as a first-class Claude Code deployment target with an AWS-published reference architecture; AWS ships integration samples for OpenCode. Enterprise deployments converge on three patterns: LiteLLM proxy + virtual keys (per-user budgets), direct Bedrock + IAM/Identity Center + CloudWatch (AWS-native attribution), and emerging direct-Mantle-with-bearer-tokens. _Sources: https://github.com/aws-solutions-library-samples/guidance-for-claude-code-with-amazon-bedrock, https://www.truefoundry.com/blog/claude-code-with-litellm-setup-guide-when-to-use-truefoundry-ai-gateway_ (Confidence: Medium-High)
- **Subscription-credential lockdown:** the March 2026 enforcement wave against third-party tools reusing Claude subscription OAuth confirms cloud-provider billing (Bedrock) as the only durable third-party path for Claude-powered products. Kiro moved the opposite direction — closed-source, subscription-only. _Sources: https://code.claude.com/docs/en/legal-and-compliance, https://kiro.dev/faq/_ (Confidence: High)
- **Mantle shift:** AWS explicitly recommends the Mantle endpoint for new apps; newest Claude models (Fable 5, Sonnet 5) are Mantle-first. Any integration built today should target Mantle-compatible configuration or keep both paths configurable. _Source: https://docs.aws.amazon.com/bedrock/latest/userguide/endpoints.html_ (Confidence: High)
- **Quota mechanics as the new scaling constraint:** output-token burndown (15x for Claude 4.8-generation, 10x for Sonnet 5 on runtime), upfront `max_tokens` reservation, and low default quotas on fresh AWS accounts are the operational realities that shape platform architecture more than raw pricing. Mantle uses separate input/output TPM pools without burndown. _Sources: https://docs.aws.amazon.com/bedrock/latest/userguide/quotas-token-burndown.html, https://docs.aws.amazon.com/bedrock/latest/userguide/quotas-mantle.html_ (Confidence: High)

---

## Integration Patterns Analysis

### Credential Provisioning — BYO Customer Account

The canonical SaaS pattern (used by Cursor, Datadog-class vendors) is a **cross-account IAM role with ExternalId**:

1. **Onboarding**: platform generates a per-customer ExternalId (never customer-chosen; not a secret; no rotation prescribed) and offers two provisioning paths — a CloudFormation quick-create link (`.../cloudformation/home#/stacks/create/review?templateURL=<S3>&param_ExternalId=...&param_PlatformAccountId=...`; customer must acknowledge CAPABILITY_IAM) and a published Terraform module. Role ARN returns via stack Outputs paste-back, a Lambda-backed custom-resource callback, or a deterministic role name. _Sources: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html, https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-console-create-stacks-quick-create-links.html, https://aws.amazon.com/blogs/apn/securely-using-external-id-for-accessing-aws-accounts-owned-by-others/_ (Confidence: High)
2. **Validation ritual** (AWS-prescribed): on ARN submission, attempt AssumeRole both with and without the ExternalId; reject the integration if it succeeds without. _Source: same IAM guide_ (Confidence: High)
3. **IAM scoping**: base policy = Claude Code's documented minimum (`bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`, `bedrock:ListInferenceProfiles`, `bedrock:GetInferenceProfile` + marketplace-subscribe conditioned on `aws:CalledViaLast: bedrock.amazonaws.com`). Global CRIS requires the **3-ARN rule**: the `global.*` inference-profile ARN, the regional foundation-model ARN, and the region-less `arn:aws:bedrock:::foundation-model/<model>` ARN with `aws:RequestedRegion: "unspecified"`, all restrictable via the `bedrock:InferenceProfileArn` condition key. Model pinning via `foundation-model/anthropic.*` patterns (Cursor's exact approach). _Sources: https://code.claude.com/docs/en/amazon-bedrock#iam-configuration, https://docs.aws.amazon.com/bedrock/latest/userguide/global-cross-region-inference.html, https://cursor.com/docs/customizing/aws-bedrock_ (Confidence: High)
4. **Per-session narrowing**: AssumeRole session policies (intersection semantics, ≤2,048 chars) pin the session to the specific inference-profile ARNs the user's plan allows; `sts:SourceIdentity` = platform user/session ID for customer-side CloudTrail attribution; session tags feed CUR cost attribution. _Sources: https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html, https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_control-access_monitor.html_ (Confidence: High)
5. **Role-chaining constraint**: platform infra creds are themselves role creds → the customer-role session is capped at **1 hour** (DurationSeconds >3600 fails on chained assumption). Plan for ≤1h sessions with refresh, not 12h sessions. _Source: https://repost.aws/knowledge-center/iam-role-chaining-limit_ (Confidence: High)
6. **Delivery into the workspace** — three options, in preference order:
   - **`awsCredentialExport` hook** (Claude Code settings.json): a workspace-local helper calls the platform's credential-vending endpoint (which assumes the customer role server-side and applies session policy + SourceIdentity); runs at session start and on every credential reload; JSON `{"Credentials":{...,"Expiration"}}`; cached until 5 min before expiry — purpose-built for cross-account vending, survives long sessions. This mirrors AWS's own enterprise guidance (credential broker + `credential_process`, quota checks before issuing). _Sources: https://code.claude.com/docs/en/amazon-bedrock#advanced-credential-configuration, https://github.com/aws-solutions-library-samples/guidance-for-claude-code-with-amazon-bedrock_ (Confidence: High)
   - **Short-term Bedrock API key**: mint via `aws-bedrock-token-generator` inside the assumed session (works with AssumeRole providers; lifetime = min(12h, generating creds' remaining lifetime) → **1h under role chaining**; region-bound; generation is client-side and not CloudTrail-logged; usage logs as `callWithBearerToken: true`). Simplest env-only injection (`AWS_BEARER_TOKEN_BEDROCK`) but **bypasses Claude Code's refresh machinery** — no hook re-mints an expired bearer token; acceptable only for sessions ≤ token lifetime. _Sources: https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys-how.html, https://github.com/aws/aws-bedrock-token-generator-python_ (Confidence: High; refresh-bypass Medium)
   - **Static STS env injection**: fits only sessions shorter than the STS session; no mid-session rotation.
7. **Onboarding friction to automate**: since 2025-10-15 serverless FMs need no manual enablement, but Anthropic models still require the one-time **use-case form** — `bedrock:PutUseCaseForModelAccess` is callable through the assumed role (collect the ~6 form fields in platform UI, submit verbatim; check `GetUseCaseForModelAccess` first; one management-account call covers an AWS Organization). **Cold-start quotas are the real friction**: fresh accounts see drastically reduced TPM/RPM (community: ~2 RPM vs 200+ on aged accounts) and increase requests are prioritized for accounts already consuming their allocation — run a quota preflight at onboarding and generate a prefilled Service Quotas request for the customer. _Sources: https://aws.amazon.com/blogs/security/simplified-amazon-bedrock-model-access/, https://docs.aws.amazon.com/bedrock/latest/APIReference/API_PutUseCaseForModelAccess.html, https://docs.aws.amazon.com/bedrock/latest/userguide/quotas-increase.html, https://dev.to/aws-builders/ultra-low-bedrock-llm-rate-limits-for-new-aws-accounts-time-to-wake-up-your-inactive-aws-accounts-3no0_ (Confidence: High on mechanics, Medium on exact community numbers)
8. **Region default**: `us-east-1` + `us.anthropic.*` profiles as default (Claude Code's own fallback), `global.*` where residency allows (cheapest, biggest pool), `eu.`/`jp.` source regions for residency-bound customers; customers can SCP-block `global.*`. _Source: https://docs.aws.amazon.com/bedrock/latest/userguide/global-cross-region-inference.html_ (Confidence: High)

**Real-world census**: Cursor = cross-account role + ExternalId (server-side assumption, closest analog); Sourcegraph Cody / Tabnine / n8n / LibreChat = customer-entered static keys or customer-side deployment; nobody surveyed passes raw STS creds from cloud to end-user machines. The platform's planned shape (assume role → short-lived creds into a *platform-controlled workspace*) = Cursor's role model + AWS's own Claude Code enterprise guidance. _Sources: https://cursor.com/docs/customizing/aws-bedrock, https://sourcegraph.com/docs/cody/enterprise/model-configuration, https://www.librechat.ai/docs/configuration/pre_configured_ai/bedrock_ (Confidence: High)

### Credential Provisioning — Platform Account (Resale)

- **Gateway plane (real-time enforcement)**: LiteLLM proxy is the dominant OSS pattern — Anthropic-format `/v1/messages` + `/v1/messages/count_tokens`, virtual keys with `max_budget`/`budget_duration`/`tpm_limit`/`rpm_limit`/expiry, team hierarchies, USD spend tracking. Redis required for cross-replica budget consistency; Postgres is the system of record. Latency overhead is config-dependent (LiteLLM's own benchmark: ~258 ms p99 for the Python proxy; third-party: <10 ms routing overhead at moderate QPS). Core metering is OSS; SSO/audit/JWT governance is enterprise-paywalled. _Sources: https://docs.litellm.ai/docs/proxy/virtual_keys, https://docs.litellm.ai/docs/proxy/db_deadlocks, https://docs.litellm.ai/blog/rust-ai-gateway-benchmarks_ (Confidence: High; latency Medium)
- **Known LiteLLM/Bedrock defects that matter for billing** (verify against pinned version): cache-token cost misaccounting (cache reads priced as full input — #27763, #19680), 1h-cache writes billed at 5m rate (#29432), count_tokens ignores `tools` (#26436) and silently falls back to a local tokenizer (#27632), beta-header forwarding incident (fixed via per-provider allowlist). **Conclusion: gateway numbers are for UX/enforcement; reconcile billing against AWS-side truth.** _Sources: https://github.com/BerriAI/litellm/issues/27763, https://github.com/BerriAI/litellm/issues/29432, https://github.com/BerriAI/litellm/issues/26436, https://docs.litellm.ai/blog/claude-code-beta-headers-incident_ (Confidence: High)
- **AWS-native attribution plane (billing-grade, hours-delayed)**: Mantle **Projects/Workspaces** (same resource; `anthropic-workspace` header on Messages calls; ≤1,000/account; IAM-restrictable per principal; tags → per-project cost lines; **no per-project quotas**) — one workspace per end-user works to ~1k users/account. **IAM-principal cost allocation** (GA 2026-04-08): CUR 2.0 `line_item_iam_principal` carries assumed-role session ARN incl. session name → set `RoleSessionName = user_id` and every CUR line is user-attributed with zero managed resources. Application inference profiles (~1,000/account/region) remain the per-app runtime-endpoint option; they share the underlying CRIS quota (attribution, not throttling). _Sources: https://docs.aws.amazon.com/bedrock/latest/userguide/projects.html, https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/iam-principal-cost-allocation.html, https://aws.amazon.com/blogs/machine-learning/optimize-your-applications-for-scale-and-reliability-on-amazon-bedrock/_ (Confidence: High)
- **Hard cutoffs — layered, because nothing Bedrock-native enforces per-user caps**: (1) gateway virtual-key budget = seconds-level primary; (2) CloudWatch token alarms → Lambda → IAM deny / key revocation = minutes-level backstop; (3) AWS Budgets deny-policy/SCP actions = hours-level catastrophic backstop (budget data refreshes ≤3×/day, 8–12h lag); (4) in-flight streams complete regardless — bound overshoot with `max_parallel_requests` + `max_tokens`. _Sources: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-controls.html, https://builder.aws.com/content/3FK1cmmfOAgyY6hu4ZH4Sn6JsRy/implementing-an-emergency-stop-control-for-amazon-bedrock-model-invocations_ (Confidence: High)
- **Capacity scaling for the resale account**: Mantle is a **separate quota pool** from runtime even for the same model (documented default: Opus 4.7 = 20M input / 4M output TPM; cache reads don't count against input TPM) — running both endpoints ≈ doubles per-account headroom. Beyond that: **AWS account sharding** (independent quotas per account, gateway load-balances across shards — AWS's published resilience pattern) and **Reserved tier** (min 100k input / 10k output TPM, 1–3-month commit, fixed $/TPM, overflow spills to Standard; margin becomes utilization-driven). Priority tier = +75% price for ~25% better output speed; Flex = −50% for latency-tolerant work. _Sources: https://docs.aws.amazon.com/bedrock/latest/userguide/quotas-mantle.html, https://aws.amazon.com/blogs/machine-learning/implementing-resilience-patterns-with-amazon-bedrock-and-llm-gateway/, https://docs.aws.amazon.com/bedrock/latest/userguide/service-tiers-inference.html, https://aws.amazon.com/bedrock/pricing/_ (Confidence: High)

### Wire Protocols and Gateway Contract

- **Two native Claude Code paths**: classic Invoke API (`InvokeModelWithResponseStream`, binary `application/vnd.amazon.eventstream`; Converse is NOT supported) and Mantle (`/anthropic/v1/messages`, Anthropic shape, SSE; SigV4 service `bedrock-mantle` or bearer token in `x-api-key`). Both can run simultaneously — Mantle-format model IDs route to Mantle, others to Invoke. _Sources: https://code.claude.com/docs/en/amazon-bedrock, https://platform.claude.com/docs/en/build-with-claude/claude-in-amazon-bedrock_ (Confidence: High)
- **Formal gateway contract** (official protocol page): Anthropic-format gateways must serve `POST /v1/messages` (match on path — actual request is `/v1/messages?beta=true`) and optionally `/v1/messages/count_tokens` (absence = approximate context display, no hard failure); forward `anthropic-beta`/`anthropic-version` verbatim as **open lists** (never allowlist values); Bedrock-format gateways serve `/model/{model}/invoke(-with-response-stream)` with beta fields in the body. **Streaming must not be buffered**; **error bodies must pass through unmodified** (Claude Code's auto-recovery matches upstream error wording). Session attribution headers available to gateways without body parsing: `x-claude-code-session-id`, `x-claude-code-agent-id`, `x-claude-code-parent-agent-id`. _Source: https://code.claude.com/docs/en/llm-gateway-protocol_ (Confidence: High)
- **Middlebox verdicts**: API Gateway + Lambda breaks the binary eventstream (named culprit in official docs; `CLAUDE_CODE_DISABLE_BEDROCK_CONTENT_TYPE_GUARD=1` only helps if the body survived); ALB passes streams but default 60s idle timeout must be raised (600s+); nginx needs `proxy_buffering off` + raised read timeouts; AWS WAF's `CrossSiteScripting_Body` rule blocks `/v1/messages` bodies (exempt the path). Client-side watchdogs: `API_TIMEOUT_MS` default 10 min; `API_FORCE_IDLE_TIMEOUT` = 5-min no-bytes abort, **active by default on Bedrock/gateway connections** — the gateway must emit a byte at least every 5 min. Retries: up to 10 with exponential backoff on 429/5xx/timeouts/dropped connections. _Sources: https://code.claude.com/docs/en/amazon-bedrock#streaming-errors-behind-a-gateway-or-proxy, https://code.claude.com/docs/en/env-vars, https://code.claude.com/docs/en/errors, https://code.claude.com/docs/en/llm-gateway-connect_ (Confidence: High)
- **Format-bridging hazards** (LiteLLM-class gateways): beta headers pair with body fields (`context_management`, `output_config`, tool `strict`/`defer_loading`) — stripping one half yields `400 Extra inputs are not permitted`; mitigation `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`; adaptive thinking sends **without** a beta header and 400s on old upstreams (`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1`). **Mantle collapses the translation problem** — Anthropic shape natively on AWS — leaving gateways only credential indirection + metering. _Sources: https://code.claude.com/docs/en/llm-gateway-protocol, https://docs.litellm.ai/docs/tutorials/claude_responses_api_ (Confidence: High)

### Fleet Provisioning of CLI Configuration

- **Managed settings**: `/etc/claude-code/managed-settings.json` + drop-in `managed-settings.d/` (alphabetical merge) — highest precedence (managed > CLI args > project local > project > user); on Bedrock, **file/MDM managed settings are the only policy channel** (server-managed settings are not delivered without Anthropic auth). Keys that matter: `env` (bake `CLAUDE_CODE_USE_BEDROCK`, region, model pins, OTel), `availableModels` (+`enforceAvailableModels`; matches provider-form IDs — `us.anthropic.` prefixes not stripped, `[1m]` stripped), `modelOverrides` (Anthropic IDs → application-inference-profile ARNs), `awsAuthRefresh`/`awsCredentialExport`/`apiKeyHelper` (the latter for Anthropic-format gateways only). Pin models explicitly: unpinned v2.1.207+ defaults to Opus-rate billing. _Sources: https://code.claude.com/docs/en/settings, https://code.claude.com/docs/en/model-config, https://code.claude.com/docs/en/amazon-bedrock_ (Confidence: High)
- **Coder integration**: official `registry.coder.com/coder/claude-code/coder` module (v5.2.0) — documented Bedrock pattern wires `coder_env` resources (`CLAUDE_CODE_USE_BEDROCK=1`, `AWS_REGION`, keys or `AWS_BEARER_TOKEN_BEDROCK`) + `model = "global.anthropic.claude-sonnet-4-5-..."`; `managed_settings` input writes `/etc/claude-code/managed-settings.d/10-coder.json`; `telemetry` input sets OTel vars and auto-appends Coder workspace identifiers. **Deprecation alert: module v5 drops Coder Tasks/agentapi support, and Coder Tasks itself enters 12-month ESR 2026-06-02 (removed in v2.37, 2026-09-01)** — for orchestration, Claude Code Agent SDK/stream-json or `opencode serve`'s HTTP API is more durable than agentapi terminal scraping. Secrets: `coder_env` + User Secrets (beta) are blessed; template parameters are explicitly discouraged for secrets; for K8s workspaces, EKS IRSA gives auto-refreshing STS creds that both Claude Code's and OpenCode's SDK chains consume natively. _Sources: https://github.com/coder/registry (claude-code module README), https://coder.com/docs/ai-coder/tasks, https://coder.com/docs/admin/security/secrets, https://github.com/coder/agentapi_ (Confidence: High)
- **OpenCode as second CLI**: `amazon-bedrock` provider block supports `endpoint` (VPC/gateway URLs) and application-inference-profile ARN model overrides; auth = `AWS_BEARER_TOKEN_BEDROCK` → full AWS chain (incl. IRSA web identity). Richer programmatic surface than Claude Code (`opencode serve` HTTP API: sessions, prompt_async, SSE events, OpenAPI 3.1). **Weakness: no `awsAuthRefresh` equivalent** (feature request open); env-injected STS creds are not re-read → prefer IRSA/instance-profile sources or restart sessions before expiry. _Sources: https://opencode.ai/docs/providers, https://opencode.ai/docs/server, https://github.com/anomalyco/opencode/issues/7045, https://github.com/anomalyco/opencode/issues/23522_ (Confidence: High)

### Usage Accounting and Metering Integration

- **OTel from workspaces**: `CLAUDE_CODE_ENABLE_TELEMETRY=1` + OTLP exporter vars; metrics `claude_code.token.usage` (type=input|output|cacheRead|cacheCreation, model, query_source), `claude_code.cost.usage` (client-side **estimate**), session/LoC/commit/PR counters; every metric carries `session.id`. Identity on Bedrock: `user.email` is absent (OAuth-only) — inject platform identity via `OTEL_RESOURCE_ATTRIBUTES` (custom keys like `platform.user.id`; built-ins can't be overridden) or OTLP headers via `otelHeadersHelper`. Cardinality: `OTEL_METRICS_INCLUDE_SESSION_ID=false` for large fleets. OTel vars are NOT propagated to subprocesses. _Source: https://code.claude.com/docs/en/monitoring-usage_ (Confidence: High)
- **Reference topology** (AWS guidance repo — pure OTel, no JSONL parsing): central OTel collector on ECS Fargate behind ALB (identity lifted from `x-user-email` header via `otelHeadersHelper`, or IAM assumed-role session name) → CloudWatch dashboards; optional EMF→Firehose→S3→Athena. For a Coder fleet: central collector per cluster; per-workspace sidecars unnecessary. _Source: https://github.com/aws-solutions-library-samples/guidance-for-claude-code-with-amazon-bedrock/blob/main/assets/docs/MONITORING.md_ (Confidence: High)
- **Joinability**: client metrics (`session.id`), gateway logs (`x-claude-code-session-id` header), and workspace JSONL transcripts (`~/.claude/projects/**/*.jsonl`, per-message tokens + costUSD; parseable by ccusage) join on session ID — three independent measurement planes. Billing-grade truth = AWS CUR (IAM-principal / project tags), hours-delayed; gateway = real-time enforcement; OTel = product analytics. _Sources: https://code.claude.com/docs/en/monitoring-usage, https://ccusage.com/guide/cost-modes_ (Confidence: High)

### AWS Marketplace Metering Integration (resale monetization)

- **BatchMeterUsage mechanics**: ≤25 UsageRecords/call, 1 MB, idempotent identical retries; records rejected ≥24h after the event; **dedup is per product/customer/hour/dimension and records are immutable once accepted** — aggregate per user/dimension into one record per hour yourself (AWS requires batching, recommends hourly, 0-quantity allowed). Unsubscribe gives **1 hour** to flush unreported usage; month-end grace until 06:00 UTC on the 1st. Design: durable queue (SQS) of hourly aggregates + CloudTrail reconciliation — **unreported usage = unbillable by design**. New SaaS products after 2026-06-01 must use `CustomerAWSAccountId`+`LicenseArn` (Concurrent Agreements). _Sources: https://docs.aws.amazon.com/marketplacemetering/latest/APIReference/API_BatchMeterUsage.html, https://docs.aws.amazon.com/marketplace/latest/userguide/metering-for-usage.html_ (Confidence: High)
- **Dimension design for tokens**: per-model-class × direction dimensions in 1k-token units (`sonnet_input_1k`, `opus_output_1k`, …) or a coarser "credits" dimension; **UsageAllocations** (≤5 tags, ≤2,500 allocations summing to record quantity) give enterprise buyers per-seat/team drill-down in their own Cost Explorer — a real selling point for a per-developer agent platform. "SaaS Contract with Consumption" = committed credits bundle + metered overage (`GetEntitlements` + `BatchMeterUsage`). _Source: https://docs.aws.amazon.com/marketplace/latest/userguide/metering-for-usage.html_ (Confidence: High; dimension naming Medium)
- **Commercials**: listing fees 3% public / 3–1.5% tiered private offers (renewals 1.5%); Marketplace purchases draw down buyer EDP commitments (commonly capped ~25% of annual commit — contractual, not public); realistic listing timeline 4–8 weeks incl. metering integration + live metering test; "AI Agents and Tools" category (launched 2025-07) fits an agent platform and adds agent-specific discovery. _Sources: https://docs.aws.amazon.com/marketplace/latest/userguide/listing-fees.html, https://www.nops.io/blog/ultimate-guide-aws-edp/, https://docs.aws.amazon.com/marketplace/latest/userguide/getting-started-ai-agents.html_ (Confidence: High for fees; Medium for EDP cap and timeline)

### End-User Cloud Authentication Flows (Kiro-Style Self-Serve Onboarding)

Product requirement: the user picks their cloud provider in the platform UI and completes a browser sign-in on their own machine; the headless workspace container obtains short-lived credentials — no static keys pasted into containers. (UX reference: Kiro's sign-in — Google/GitHub/Builder ID or "Your organization" → IAM Identity Center Start URL + region → browser SSO. Note: Kiro's flow authorizes its *subscription* service; the pattern below reuses the same UX shape to authorize *Bedrock/Vertex/Foundry* directly.)

**AWS — IAM Identity Center (the direct Kiro-flow analog):**
- Config = `[sso-session]` block (+ profile with `sso_account_id`/`sso_role_name`) in `~/.aws/config`; this form supports automated token refresh (legacy profile-only form does not). Since AWS CLI 2.22.0 an Issuer URL may replace the Start URL. _Source: https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html_ (Confidence: High)
- **Critical 2026 detail: PKCE became the CLI default (v2.22.0+) and cannot work cross-device** — its URL must open on the machine running the CLI. Headless containers must force the device grant: `aws sso login --profile X --use-device-code` prints a URL (`https://device.sso.<region>.amazonaws.com/`) + short code (`QCFK-N451`) — relay both into the platform UI; user completes on their own browser. _Source: same page_ (Confidence: High)
- Claude Code consumes SSO profiles natively (`AWS_PROFILE` + documented Option C); on expiry, `awsAuthRefresh: "aws sso login --profile X --use-device-code"` re-runs the flow — its stdout is shown to the user, explicitly designed "for browser-based SSO flows where the CLI displays a URL or code". SDK auto-renews role creds while the IdC session lives (session length is org-configured; access portal default 8h, permission-set role creds 1h default/12h max — Medium confidence on exact lifetimes). _Source: https://code.claude.com/docs/en/amazon-bedrock_ (Confidence: High; lifetimes Medium)

**AWS — no Identity Center (individual accounts):**
- **`aws login` (CLI ≥ 2.32.0)** — new sign-in command recommended for console users; `aws login --remote` is the cross-device variant for browserless machines; session valid up to 12h; IAM users need the `SignInLocalDevelopmentAccess` managed policy. Claude Code documents it as Option D. Least-friction no-static-keys path for SSO-less users. _Sources: https://docs.aws.amazon.com/signin/latest/userguide/command-line-sign-in.html, https://code.claude.com/docs/en/amazon-bedrock_ (Confidence: High; `--remote` terminal UX Medium)
- Fallbacks: short-term Bedrock API key (`AWS_BEARER_TOKEN_BEDROCK`), long-term key/static keys (violates the no-static-keys goal).

**Google Vertex AI (Google Cloud's Agent Platform):**
- Config: `CLAUDE_CODE_USE_VERTEX=1`, `ANTHROPIC_VERTEX_PROJECT_ID`, `CLOUD_ML_REGION=global` (+ per-model region overrides `VERTEX_REGION_CLAUDE_*`). Gotcha: `GOOGLE_CLOUD_PROJECT`/`GOOGLE_APPLICATION_CREDENTIALS` take precedence over `ANTHROPIC_VERTEX_PROJECT_ID`. IAM: `roles/aiplatform.user`. _Source: https://code.claude.com/docs/en/google-vertex-ai_ (Confidence: High)
- Headless login: `gcloud auth application-default login --no-launch-browser` — prints a URL; after consent Google shows an authorization code the user must **paste back** into the terminal (an extra UI step vs the AWS/Azure device flows; the platform UI must host the paste-back). OOB flow was removed in 2023; `--no-browser` variant requires a second gcloud-equipped machine — not usable here. _Sources: https://cloud.google.com/sdk/gcloud/reference/auth/application-default/login, https://developers.googleblog.com/en/making-google-oauth-interactions-safer/_ (Confidence: Medium — training-data verified, not re-fetched)
- Refresh: ADC refresh token auto-renews 1h access tokens indefinitely (absent org session policy); forced re-auth covered by the **`gcpAuthRefresh`** hook (verified name; stdout shown to user; **3-minute timeout** — a hard budget for the browser round-trip). _Source: https://code.claude.com/docs/en/google-vertex-ai_ (Confidence: High)

**Microsoft Foundry (Azure):**
- Config: `CLAUDE_CODE_USE_FOUNDRY=1` + `ANTHROPIC_FOUNDRY_RESOURCE` (or `ANTHROPIC_FOUNDRY_BASE_URL=https://{resource}.services.ai.azure.com/anthropic`). Three auth options: (A) `ANTHROPIC_FOUNDRY_API_KEY`; (B) **empty env → Azure SDK default credential chain (Entra ID)** — the recommended no-keys path; (C) `ANTHROPIC_FOUNDRY_AUTH_TOKEN` static bearer (v2.1.203+, dies at ~1h — avoid for long sessions). RBAC: `Azure AI User` + `Cognitive Services User`. **No azureAuthRefresh hook exists or is needed** — the chain mints/refreshes tokens per request from the `~/.azure` cache. _Source: https://code.claude.com/docs/en/microsoft-foundry_ (Confidence: High)
- Headless login: `az login --use-device-code` → classic `microsoft.com/devicelogin` + code; refresh token cached in `~/.azure`, chain auto-refreshes 60–90-min access tokens. **Cleanest device flow of the three.** _Source: https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-interactively_ (Confidence: Medium — training-data verified)
- Billing: Foundry is a normal Azure resource — usage lands on the customer's Azure invoice (Confidence: High); MACC eligibility of Claude-in-Foundry consumption stated around the late-2025 Microsoft–Anthropic announcements but **not re-verified — confirm before promising in marketing** (Confidence: Medium). _Source: https://azure.microsoft.com/en-us/pricing/details/ai-foundry/_

**Per-provider container payload and expiry survival:**

| Provider | Lands in container | Headless login UX | Long session survives expiry? |
|---|---|---|---|
| Bedrock (IdC SSO) | `~/.aws/config` (sso-session+profile), `CLAUDE_CODE_USE_BEDROCK=1`, `AWS_PROFILE` | `aws sso login --use-device-code` → URL + code, no paste-back | Yes — SDK auto-renews while IdC session lives; then `awsAuthRefresh` re-runs device flow |
| Bedrock (plain IAM) | nothing pre-provisioned / `AWS_BEARER_TOKEN_BEDROCK` | `aws login --remote` → browser sign-in | ≤12h; re-run login (wireable as `awsAuthRefresh` — unverified) |
| Vertex | `CLAUDE_CODE_USE_VERTEX=1`, project+region envs; ADC file after login | `gcloud ... --no-launch-browser` → URL out, **code paste-back** | Yes — ADC refresh token; `gcpAuthRefresh` (3-min timeout) for forced re-auth |
| Foundry | `CLAUDE_CODE_USE_FOUNDRY=1`, resource env; `~/.azure` cache after login | `az login --use-device-code` → devicelogin + code | Yes — Entra chain auto-refreshes; no hook needed |

**Refresh-hook inventory (verified):** AWS → `awsAuthRefresh` + `awsCredentialExport`; GCP → `gcpAuthRefresh`; Azure/Foundry → none (chain-delegated). _Sources: the three code.claude.com provider pages_ (Confidence: High)

**Alternative for BYO-AWS without any user-side login:** the platform-vended credential pattern (cross-account role + `awsCredentialExport` helper, section above) needs no browser flow at all — the user connects the AWS *account* once (CloudFormation), and workspaces silently receive short-lived creds. The device-flow UX is the right fit when the *end user* (not the org) owns the cloud account, or when the org's security posture forbids cross-account roles. AWS's own guidance repo takes a third road: packaged login CLI → org OIDC IdP → Cognito → STS broker (Confidence: Medium on details). Design synthesis: **offer "Connect organization account" (cross-account role, zero per-user friction) and "Sign in with your cloud" (device flows above) as two tiers of the same provider-connect UI** — mirroring Kiro's Builder-ID-vs-organization split.

### Integration Security Patterns

- **Confused-deputy protection**: ExternalId (platform-generated, per customer account, immutable in-product) + the with/without validation test; `sts:SourceIdentity` for per-user attribution in customer CloudTrail; session policies to pin per-session model access. _Sources: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html, https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_control-access_monitor.html_ (Confidence: High)
- **Credential hygiene**: prefer STS temporary creds > short-term Bedrock API keys > long-term keys (AWS's stated hierarchy); long-term keys governable via `iam:ServiceSpecificCredentialAgeDays` and `bedrock:bearerTokenType` conditions; short-term key generation is not CloudTrail-logged (client-side presigning) — log vending in the platform. _Sources: https://aws.amazon.com/blogs/security/securing-amazon-bedrock-api-keys-best-practices-for-implementation-and-management/, https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys.html_ (Confidence: High)
- **Customer-side guardrails to document**: SCP snippets for region pinning (must allow `aws:RequestedRegion: "unspecified"` if global CRIS is used — or deny `inference-profile/global.*` to forbid it), model denylists, Bedrock Guardrails via `ANTHROPIC_CUSTOM_HEADERS` (`X-Amzn-Bedrock-GuardrailIdentifier`). _Sources: https://docs.aws.amazon.com/bedrock/latest/userguide/global-cross-region-inference.html, https://code.claude.com/docs/en/amazon-bedrock_ (Confidence: High)
- **Data-path trade-off**: direct-from-workspace Bedrock calls keep prompts inside the customer's trust boundary (strongest BYO story); a platform-side signing gateway (LiteLLM `aws_role_name`+`aws_external_id`) centralizes control but routes prompts through platform infra — surface this in security documentation. _Sources: https://docs.litellm.ai/docs/providers/bedrock, https://github.com/BerriAI/litellm/pull/14582_ (Confidence: High)

---

## Architectural Patterns and Design

### System Architecture Patterns — AWS's Two Blessed Shapes

AWS's current published guidance converges on exactly two architectures for multi-user LLM platforms, mapping cleanly onto the two billing models:

1. **Direct, gateway-less (credential-layer control)** — AWS's own "Guidance for Claude Code with Amazon Bedrock": OIDC IdP → `AssumeRoleWithWebIdentity` via a local credential-process helper → **clients call Bedrock directly** ("Rather than maintaining a gateway between clients and Bedrock, the architecture enables direct API calls"). Governance without a data-path proxy: a Lambda checks CloudWatch usage against per-user/team DynamoDB quota policies and **withholds credentials** when limits are exceeded. Rationale: zero added latency, no proxy ops, native IAM/CloudTrail attribution. Natural fit for **BYO**. _Source: https://github.com/aws-solutions-library-samples/guidance-for-claude-code-with-amazon-bedrock_ (Confidence: High)
2. **Centralized LiteLLM-class gateway** — the Well-Architected **Generative AI Lens "Multi-tenant generative AI platform scenario"** (updated 2025-11-19) explicitly prescribes LiteLLM on ECS/EKS: tenant onboarding via virtual keys, per-tenant rate limits/tiers/quotas enforced at the gateway (in-memory + persistent), RDS for tenant configs/cost records, Redis for request + semantic caching, latency-aware/error/fallback routing. Same shape as the "Multi-Provider Generative AI Gateway" solutions guidance (2025-11-21). Natural fit for **resale**. _Sources: https://docs.aws.amazon.com/wellarchitected/latest/generative-ai-lens/multi-tenant-generative-ai-platform-scenario.html, https://aws.amazon.com/blogs/machine-learning/streamline-ai-operations-with-the-multi-provider-generative-ai-gateway-reference-architecture/_ (Confidence: High)

The June-2026 resilience blog gives the decision list for when a gateway is warranted: HA needs, scaling beyond single-account quotas, **SaaS multi-tenancy**, dev/prod separation. Note the published trade-off catalog is asymmetric — AWS does not discuss gateway latency/SPOF downsides; those appear only in vendor/community material. _Source: https://aws.amazon.com/blogs/machine-learning/implementing-resilience-patterns-with-amazon-bedrock-and-llm-gateway/_ (Confidence: High)

### Candidate End-to-End Architectures

| | **A. BYO direct** | **B. BYO via platform gateway** | **C. Resale (gateway + Marketplace)** | **D. Hybrid (recommended shape)** |
|---|---|---|---|---|
| Token spend lands | Customer's Bedrock | Customer's Bedrock | Platform's Bedrock | Both (per customer tier) |
| Data path | Workspace → Bedrock directly | Workspace → platform gateway → Bedrock | Workspace → gateway → Bedrock | Tiered |
| Quota pool | Per customer account (isolation free) | Per customer account | Platform account (shared; shard + Mantle) | Both |
| Per-user limits | Credential-layer (vending gate) | Gateway virtual keys | Gateway virtual keys | Both |
| Privacy story | Strongest (prompts never leave customer boundary) | Weaker (prompts transit platform) | Platform holds prompts | Tiered |
| Platform revenue | Software fee only | Software fee only | Token margin + fee | Fee via Marketplace + optional token resale |
| AWS partnership value | Consumption story (ACE), 100% EDP burn | Same as A | Marketplace GMV, quota retirement | **Both consumption story AND quota event** |
| Ops burden | Lowest | Gateway ops | Gateway + metering pipeline + quota management | Highest |

(Confidence: High on mechanics per prior sections; D-recommendation is synthesis, Medium-High)

### Tenant Isolation and Noisy-Neighbor Design

- **Silo/pool/bridge** applied to LLM inference (AWS AgentCore multi-tenancy blog, 2026-05-21): silo = max isolation/cost, pool = cheapest but "poor" noisy-neighbor protection, bridge = choose tenancy per layer. Most SaaS "start pooled… introduce silos for premium or regulated tenants." BYO is inherently silo'd (each customer's TPM quota is their own); resale is pooled and needs gateway fairness. _Source: https://aws.amazon.com/blogs/machine-learning/building-multi-tenant-agents-with-amazon-bedrock-agentcore/_ (Confidence: High)
- **ABAC with session tags** for pooled isolation: tenant identity as session tag (`sts:TagSession`), policies conditioned on `aws:PrincipalTag/TenantID`. _Source: https://aws.amazon.com/blogs/machine-learning/shared-infrastructure-isolated-tenants-pool-model-multi-tenancy-with-amazon-bedrock-agentcore/_ (Confidence: Medium-High)
- **Noisy-neighbor doctrine**: per-consumer rate-limit buckets at the gateway (resilience pattern #5); Bedrock reserves quota by `max_tokens` at request start — **client-set max_tokens must be a platform-governed parameter**; Bedrock itself is multi-tenant (community-measured ~2s→6s latency swings at US peak). _Sources: https://aws.amazon.com/blogs/machine-learning/implementing-resilience-patterns-with-amazon-bedrock-and-llm-gateway/, https://repost.aws/knowledge-center/bedrock-throttling-error_ (Confidence: High; latency anecdote Medium)
- **Third isolation axis (2026-07): Bedrock Projects** — workload isolation within one account on `bedrock-mantle`, incl. **per-project data-retention policies**; AWS frames the choice as "projects within one account vs separate accounts by retention requirement." _Source: https://aws.amazon.com/blogs/security/enforce-zero-data-retention-on-amazon-bedrock-with-bedrock-projects-and-service-control-policies/_ (Confidence: High)

### Deployment and Operations Architecture

- **Model lifecycle you inherit**: Active → Legacy → EOL; providers give ≥6 months' notice; in Legacy, new provisioned throughput is unavailable and **quota increases are not expected to be approved**; migration is never automatic. **Bedrock's retirement calendar diverges from Anthropic's first-party API calendar** — a platform serving both tracks two clocks (e.g. Claude 3.5 Sonnet v2 EOL on Bedrock 2026-07-30). _Sources: https://aws.amazon.com/blogs/machine-learning/understanding-amazon-bedrock-model-lifecycle/, https://platform.claude.com/docs/en/about-claude/model-deprecations_ (Confidence: High)
- **Version-upgrade doctrine** (AWS-published): shadow testing → A/B on live traffic percentage → canary/blue-green with rollback; build custom benchmarks from production traffic; evaluate with exact production guardrail config. Gateway weighted routing is the mechanical lever. _Source: https://aws.amazon.com/blogs/machine-learning/migrate-from-anthropics-claude-sonnet-3-x-to-claude-sonnet-4-x-on-amazon-bedrock/_ (Confidence: High)
- **Failover layering**: CRIS/global-CRIS solves *regional capacity* beneath the app; gateway model-fallback solves *model/provider/quota* failures above it — they compose. With CRIS, retained inputs/outputs (for retention-requiring models) are stored in **destination** regions — a data-residency footnote for customer docs. _Sources: https://aws.amazon.com/blogs/machine-learning/implementing-resilience-patterns-with-amazon-bedrock-and-llm-gateway/, https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html_ (Confidence: High)

### Data Architecture — Logging, Retention, and the June 2026 ZDR Regime

- **Invocation logging is off by default**; when enabled it captures full request/response bodies to CloudWatch/S3 in the owning account. BYO: logging/retention/CloudTrail are customer-owned; platform sees prompts only where its components sit on the data path (never, in architecture A). Resale: platform owns the switch — enabling it stores customer prompts in platform infra (deliberate compliance decision; Gen AI Lens advises metadata-only logging). _Sources: https://docs.aws.amazon.com/bedrock/latest/userguide/model-invocation-logging.html, Gen AI Lens scenario_ (Confidence: High)
- **The biggest new architecture input — Bedrock data-retention modes (landed ~2026-06-09)**: `default` / `provider_data_share` / `none` (ZDR) / `inherit`, resolved project → account → model default; API-only configuration; SCP-enforceable via `bedrock:DataRetentionMode` condition keys. **Claude Fable 5 and Mythos 5 REQUIRE `provider_data_share`** — prompts/completions shared with Anthropic, retained up to 30 days for trust & safety; models show `unavailable` without the opt-in. ZDR exceptions negotiable per account+model via the AWS account manager. Platform implications: resale offering Fable-5-class models must disclose the 30-day Anthropic retention in customer contracts (Bedrock Projects scope the opt-in per tenant); BYO pushes the decision to the customer — the platform must gracefully handle "model unavailable under retention mode" per tenant. _Sources: https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html, https://aws.amazon.com/blogs/security/enforce-zero-data-retention-on-amazon-bedrock-with-bedrock-projects-and-service-control-policies/_ (Confidence: High)

### Partnership Alignment as an Architecture Driver

The partnership research reframes the BYO-vs-resale question:

- **The formal AWS ladder gates on Marketplace transacting, not consumption.** ISV Accelerate entry: GA transactable Marketplace listing, Validated/Differentiated stage, ACE eligibility, ≥5 launched + ≥15 qualified ACE opportunities (trailing 12 months), ≥$2,000 recognized AWS revenue, Payee Central, co-sell training. **AM quota retirement exists only for Marketplace private offers** (SaaS Co-Sell Benefit, open to all ISV Accelerate partners since 2025-01). Pure BYO with no listing caps out at "Validated software partner" with no co-sell program. _Source: https://aws.amazon.com/partners/programs/isv-accelerate/_ (Confidence: High)
- **But BYO consumption counts formally too**: ACE opportunities carry a mandatory "Estimated AWS Monthly Recurring Revenue" field — each BYO customer registers as an ACE opportunity whose AWS MRR = projected Bedrock spend; these satisfy the 15/5 thresholds and (2026 rule) specialization renewals. Customer-side economics strongly favor BYO: native Bedrock spend burns EDP commits at **100% with the EDP discount**, vs Marketplace's **~25% cap without discount**; AWS Activate credits **can** pay for Claude on Bedrock (since 2024-04) — startup customers burn free credits on your product. _Sources: https://aws.amazon.com/blogs/awsmarketplace/improving-your-visibility-to-aws-sales-a-practical-guide-for-partners/, https://www.nops.io/blog/ultimate-guide-aws-edp/, https://awsinsider.net/articles/2024/04/04/aws-activate-credits-bedrock-access.aspx_ (Confidence: High)
- **Hard constraint on resale (2025-05-01 rule)**: only SaaS **fully deployed on AWS** qualifies for customer commit retirement — a resale platform must run entirely on AWS for its Marketplace revenue to burn customer EDPs. _Source: https://leadiq.com/blog/aws-ppa-formerly-edp-how-to-use-your-committed-spend-on-saas-tools_ (Confidence: High)
- **The documented winning pattern is hybrid** (Writer, Perplexity, Glean): run on AWS + drive Bedrock consumption (ACE-registered) + transact at least the platform fee via Marketplace private offers in the **AI Agents & Tools category** + pursue AI Competency/Agentic specialization ($50K + $25K MDF) for invite-only motions (PIA ISV Pods, Partner Agent Factory, SCAs). Notably: **Coder has a Strategic Collaboration Agreement with AWS** for exactly this space — directly relevant to a Coder-based platform. Counter-example: Cursor has no visible AWS partnership, yet AWS community actively publishes BYO-Bedrock routing guides for it — AWS's field promotes the BYO pattern for coding agents unilaterally. _Sources: https://aws.amazon.com/blogs/apn/aws-launches-partner-innovation-alliance-isv-pods-to-accelerate-enterprise-generative-ai-innovation, https://coder.com/blog/coder-signs-strategic-collaboration-agreement-with-aws, https://builder.aws.com/content/3FXvkUKPwbmbqHeNo9DI4NxrrH2/cursor-meets-bedrock-route-every-ai-coding-request-through-your-own-aws-account_ (Confidence: High; hybrid synthesis Medium-High)
- **The Anthropic axis is separate**: Claude Partner Network (launched 2026-03-12, $100M/2026, free, cloud-agnostic — services-tiered today, no ISV track yet); Claude startup credits apply **only to the first-party API, not Bedrock**; subscription-OAuth brokering remains prohibited. Bedrock routing builds AWS-side leverage, none with Anthropic; the platform can join CPN regardless. _Sources: https://www.anthropic.com/news/claude-partner-network, https://claude.com/programs/startups_ (Confidence: High)
- **Ladder timeline**: APN $2,500/yr (incl. $3,500 credits) → Marketplace listing → FTR (~40–80h prep; decisions now minutes, Bedrock-automated) → Validated → 12 months of ACE pipeline → ISV Accelerate → AI Competency. Realistically ~9–18 months to full co-sell status. _Sources: https://aws.amazon.com/partners/foundational-technical-review/, https://labra.io/aws-partner-programs-guide/_ (Confidence: Medium-High)

### Validation From Adjacent Architectures

- AWS itself now hosts coding-agent CLIs (Claude Code, Codex CLI, Kiro CLI, Cursor CLI, OpenCode) in per-session Firecracker microVMs on **Bedrock AgentCore** with a Token-Vault credential broker — architectural validation of the per-user-workspace + brokered-credentials pattern (and a potential competitor). _Source: https://aws.amazon.com/blogs/machine-learning/its-safe-to-close-your-laptop-now-hosting-coding-agents-on-amazon-bedrock-agentcore/_ (Confidence: High)
- No commercial multi-tenant coding-agent SaaS publishes its Bedrock account topology — the citable architectures are AWS's own guidance artifacts (confidence in absence: High after targeted search).

---

## Implementation Approaches and Technology Adoption

### Fit With the Existing Codebase

The platform already has the seams Bedrock integration needs (verified in-repo):

- **CLI adapter pattern**: `app/services/agents/claude_code_adapter.rb` (also `cursor_cli_adapter.rb`, `gemini_cli_adapter.rb`; registry in `app/services/agent_credentials_service.rb:6`). Bedrock config = new env vars in the adapter's `default_env_vars` (`claude_code_adapter.rb:331`) + `session_command` (`:251`).
- **Env assembly / launch**: `app/services/container_strategies/agent_base_strategy.rb:88` (`build_env_vars`) → `agent_session_strategy.rb:114` (`launch_agent_in_tmux`); Temporal manifest at `agent_base_strategy.rb:38`.
- **Credential machinery**: `app/models/agent_credential.rb` (encrypted per user/agent; `generate_container_config`:101; `write_to_container` via `session_context_service.rb:126`) and `app/models/oauth_credential.rb` + `app/services/oauth/token_service.rb` (multi-provider, per_user/shared scopes). A Bedrock credential becomes a new `AgentCredential` variant (STS role ref / SSO profile / bearer token).
- **Login-session surface**: `app/models/terminal_session.rb:113` dispatches `auth_setup` → `AgentAuthStrategy` — the natural host for device-flow sign-in sessions (`aws sso login --use-device-code`, `aws login --remote`, `gcloud ... --no-launch-browser`, `az login --use-device-code`).
- **Coder side**: `app/services/coder/allocator.rb`, `workspace_service.rb`, `ssh_runner.rb` for provisioning and in-workspace execution.

(Confidence: High — direct code inspection 2026-07-24)

### Technology Adoption Strategy (Phased Roadmap)

**Phase 0 — Spike (days):** feature-flag a Bedrock mode in `claude_code_adapter`: `CLAUDE_CODE_USE_BEDROCK=1`, `AWS_REGION`, pinned `ANTHROPIC_MODEL`/`ANTHROPIC_DEFAULT_*_MODEL` (mandatory — unpinned v2.1.207+ bills at Opus rates), creds via `AWS_BEARER_TOKEN_BEDROCK` from a test account. Validates the whole path with ~zero new infra. _Source: https://code.claude.com/docs/en/amazon-bedrock_
**Phase 1 — Self-serve BYO for individuals (weeks):** provider-connect UI (AWS first); device flows in `AgentAuthStrategy` sessions: Identity Center (`aws sso login --use-device-code`, sso-session config templated into `~/.aws/config`) and no-SSO (`aws login --remote`, CLI ≥2.32); `awsAuthRefresh` wired in settings.json; surface hook stdout (URL+code) in the session UI. Mirrors the Kiro sign-in UX.
**Phase 2 — Org BYO (weeks–month):** cross-account role onboarding (CloudFormation quick-create + Terraform module, ExternalId validation ritual), platform vending endpoint + workspace `awsCredentialExport` helper (1h role-chained sessions, auto re-vend), `PutUseCaseForModelAccess` automation, quota preflight report, per-user `RoleSessionName`/`SourceIdentity` for CUR/CloudTrail attribution. This is the architecture-A shape AWS's own guidance blesses. _Source: https://github.com/aws-solutions-library-samples/guidance-for-claude-code-with-amazon-bedrock_
**Phase 3 — Partnership track (parallel, months):** APN registration → transactable AWS Marketplace SaaS listing (platform fee; "AI Agents and Tools" category) → FTR (~40–80h prep) → register every BYO customer as an ACE opportunity with Estimated AWS MRR = projected Bedrock spend → ISV Accelerate once 5/15 thresholds accumulate. _Source: https://aws.amazon.com/partners/programs/isv-accelerate/_
**Phase 4 — Optional resale tier:** LiteLLM gateway + virtual keys (budgets/limits), Mantle endpoint for capacity + native Anthropic shape, Marketplace metered dimensions via hourly `BatchMeterUsage` pipeline, CUR reconciliation. Gate on demonstrated demand — it adds the metering pipeline, quota management, and (since June 2026) the `provider_data_share` disclosure burden for Fable-5-class models.
**Parallel track — multi-cloud:** the same provider-connect UI extends to Vertex (`CLAUDE_CODE_USE_VERTEX`, `gcpAuthRefresh`, ADC paste-back flow) and Foundry (`CLAUDE_CODE_USE_FOUNDRY`, Entra chain, `az login --use-device-code`) with per-provider adapters over the same `AgentCredential` surface. _Sources: https://code.claude.com/docs/en/google-vertex-ai, https://code.claude.com/docs/en/microsoft-foundry_

Delivery-model framing for customers (three lanes, per community cost guide): Anthropic subscription (existing), Bedrock BYO, Bedrock resale — with break-even guidance per team size. _Source: https://hidekazu-konishi.com/entry/claude_code_and_desktop_org_rollout_cost_guide.html_ (Confidence: Medium)

### Development Workflows and Tooling

- **Settings provisioning**: template `~/.claude/settings.json` env blocks (or `/etc/claude-code/managed-settings.d/10-platform.json` baked into workspace images) from `AgentCredential#generate_container_config`; per-workspace values via `coder_env`-equivalent env injection at `build_env_vars`.
- **OpenCode as second CLI**: add adapter with `amazon-bedrock` provider block; reuse the same credential surface; prefer IRSA/instance-profile creds for its sessions (no refresh hook).
- **Gateway (Phase 4 only)**: LiteLLM `/v1/messages` with virtual keys; pin and regression-test the LiteLLM version against the documented gateway protocol (`/v1/messages/count_tokens`, beta-header passthrough, eventstream integrity). _Source: https://code.claude.com/docs/en/llm-gateway-protocol_

### Testing and Quality Assurance

- Per repo testing doctrine (`docs/testing.md`): stub the app-owned adapter seams, never the vendor SDK — introduce a fake STS/Bedrock credential vendor and a fake token generator behind the vending endpoint; contract-test `generate_container_config` outputs (env vars, settings.json shape) per provider.
- Device-flow UX: integration-test the `AgentAuthStrategy` session lifecycle with a scripted fake CLI that prints URL+code; assert the platform surfaces them.
- Model migrations: adopt AWS's shadow → A/B → canary doctrine with production-derived benchmarks before switching pinned model IDs; keep the two deprecation calendars (Bedrock vs Anthropic API) in an ops runbook. _Source: https://aws.amazon.com/blogs/machine-learning/migrate-from-anthropics-claude-sonnet-3-x-to-claude-sonnet-4-x-on-amazon-bedrock/_

### Deployment and Operations Practices

- **Telemetry**: central OTel collector per cluster; workspaces export `claude_code.token.usage`/`cost.usage` with `platform.user.id` resource attrs; joinable with gateway logs (`x-claude-code-session-id`) and JSONL transcripts. _Source: https://code.claude.com/docs/en/monitoring-usage_
- **Quota ops**: TPM/RPM dashboards per customer account (BYO) and per shard (resale); alert on 429 ThrottlingException rates; govern `max_tokens`; quota-increase playbook with prefilled Service Quotas requests. _Source: https://repost.aws/knowledge-center/bedrock-throttling-error_
- **Cost attribution**: BYO — IAM-principal CUR lines via per-user `RoleSessionName` (zero managed resources); resale — Mantle Projects per tenant + gateway spend logs reconciled against CUR. _Source: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/iam-principal-cost-allocation.html_

### Team Organization and Skills

New competencies required: AWS IAM/STS federation design (cross-account, ExternalId, session policies), FinOps for token economics (CUR 2.0, cost allocation), AWS Marketplace seller ops (listing, private offers, metering), partner-program management (ACE pipeline discipline — 2026 rules make launched opportunities mandatory for specialization renewals). One engineer-owner for the "cloud connectivity" surface + shared PM/BD ownership of the partnership ladder is a realistic minimum. (Confidence: Medium — synthesis)

### Cost Optimization and Resource Management

- **Prompt caching is the single highest-impact lever** (~0.1x cached reads; agentic coding is the ideal caching workload); it is on by default in Claude Code on Bedrock — monitor cache-hit tokens for regressions (a broken gateway silently 10x's cost, as OpenCode's #11662 showed). 1h TTL (`ENABLE_PROMPT_CACHING_1H=1`) costs 2x writes vs 1.25x — model per workload. _Sources: https://caylent.com/blog/prompt-caching-saving-time-and-money-in-llm-applications, https://aws.amazon.com/blogs/machine-learning/supercharge-your-development-with-claude-code-and-amazon-bedrock-prompt-caching_
- **Model economics**: pin Sonnet-class defaults (Opus-by-default is a silent 1.7–2.5x cost step); global profiles ≈ 10% cheaper than regional; Flex tier (−50%) for background/batch agent work; Bedrock batch (−50%) for offline jobs; Sonnet 5 promo $2/$10 through 2026-08-31. Anthropic's published benchmark: ~$13/developer/active day, 90% under $30/day — the sizing anchor for margin/credit models. _Sources: https://aws.amazon.com/bedrock/pricing/, https://code.claude.com/docs/en/costs, https://www.cloudzero.com/blog/claude-on-aws-bedrock/_
- **Quota-aware costs**: cache reads don't burn quota (both endpoints); Mantle exempts cached reads from input TPM — cache discipline is simultaneously a cost and a capacity strategy. _Source: https://docs.aws.amazon.com/bedrock/latest/userguide/quotas-mantle.html_

### Risk Assessment and Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| Cold-start quotas in fresh customer accounts (BYO) | High | Quota preflight + prefilled increase requests; set expectations at onboarding; prefer global profiles |
| LiteLLM metering bugs (cache tokens) corrupt billing (resale) | High | CUR reconciliation as billing truth; pin + regression-test gateway version |
| Unpinned model default → Opus-rate billing | High | Mandatory model pinning in managed settings |
| `provider_data_share` requirement for Fable-5-class models (June 2026 regime) | Medium-High | Per-tenant Bedrock Projects opt-in; contract disclosures; graceful "model unavailable" handling |
| Coder Tasks/agentapi deprecation (ESR 2026-06, removed v2.37) | Medium | Migrate orchestration to Agent SDK/stream-json or `opencode serve` API |
| Bedrock model EOL cadence ≠ Anthropic's | Medium | Dual deprecation calendar + migration playbook (shadow/A-B/canary) |
| AWS competes directly (Kiro, AgentCore hosting coding agents) | Medium | Differentiate on multi-cloud + platform features; partnership makes AWS an ally channel |
| Role-chaining 1h session cap breaks long agent runs | Medium | `awsCredentialExport` auto re-vend; never rely on static env creds |
| WebSearch tool unavailable on Bedrock | Low | Document delta; WebFetch/MCP alternatives |

(Confidence: High on facts, Medium on severity ranking)

## Technical Research Recommendations

### Implementation Roadmap

1. **Now**: Phase 0 spike + model-pinning hygiene; decide default region/profile strategy (us-east-1 + `us.` profiles, `global.` where possible).
2. **Next 1–2 months**: Phase 1 (device-flow BYO for individuals — the Kiro-style UX) + Phase 2 (org cross-account onboarding). Ship the provider-connect UI with AWS first, Vertex/Foundry stubs visible ("coming soon") to signal multi-cloud.
3. **Parallel from day 1**: Phase 3 partnership motions — APN registration, Marketplace listing prep, ACE pipeline discipline for every BYO customer.
4. **Later, demand-gated**: Phase 4 resale tier (gateway + Marketplace metering + Mantle).

### Technology Stack Recommendations

- **Primary CLI**: Claude Code on Bedrock (sanctioned, richest Bedrock integration, already the platform's incumbent). **Secondary**: OpenCode (MIT, first-class Bedrock, HTTP server surface). **Avoid**: Kiro CLI (incompatible), Crush (caching disabled + FSL), aider (stagnant).
- **BYO data path**: direct-from-workspace Bedrock calls (no gateway) with credential-layer controls. **Resale data path**: LiteLLM in front of Mantle.
- **Endpoints**: keep both classic Invoke and Mantle configurable; Mantle-first for new work (newest models, better quota shape, native Anthropic wire format).

### Skill Development Requirements

AWS IAM/STS federation; Bedrock capacity/FinOps (burndown, CUR); Marketplace seller + metering ops; partner-program management (ACE/FTR/ISV Accelerate).

### Success Metrics and KPIs

- **Business**: attributed Bedrock consumption ($/mo) across customer accounts; # connected AWS accounts; ACE opportunities registered/launched; Marketplace GMV (once listed); time-to-ISV-Accelerate.
- **Product**: provider-connect funnel conversion (start → creds live in workspace); % sessions on Bedrock; session survival rate across credential refresh.
- **Ops/cost**: cache-hit token ratio; 429 rate per account; $/developer/day vs the ~$13 benchmark; gateway-vs-CUR billing variance (resale).

---

## Research Synthesis: Landing Agent Token Spend on AWS Bedrock

### Executive Summary

Amazon has invested $13B+ in Anthropic (with up to $20B more committed) and over 100,000 customers now run Claude on Amazon Bedrock — Bedrock is AWS's strategic rail for enterprise Claude consumption, and agentic coding is its fastest-growing workload. For a coding-agent platform, routing user token spend onto Bedrock is simultaneously a technical integration choice and a partnership-economics choice. This research examined both, across every viable agentic CLI, both billing architectures, and the AWS partner ladder. _Sources: https://www.aboutamazon.com/news/aws/amazon-invests-additional-4-billion-anthropic-ai, https://www.anthropic.com/news/anthropic-amazon-compute, https://aws.amazon.com/bedrock/anthropic/_

The headline answers:

1. **Kiro CLI — the presumed "Amazon-native" path — is a dead end** for this goal: closed-source, subscription-billed (line item "Kiro", never Bedrock), no BYO-Bedrock (open unanswered feature request), and its ToS prohibits third-party-harness embedding.
2. **Claude Code — already the platform's incumbent CLI — is the strongest Bedrock vehicle**: first-class `CLAUDE_CODE_USE_BEDROCK`/`CLAUDE_CODE_USE_MANTLE` support, full AWS credential-chain + refresh hooks, and — decisively — Anthropic's commercial terms *sanction* exactly this pattern (cloud-provider auth for platform-provisioned Claude Code) while prohibiting subscription-OAuth brokering. OpenCode (MIT) is the credible second CLI; Crush/aider/Codex CLI/Gemini CLI all fail on cost, staleness, or model support.
3. **The Kiro-style self-serve UX the platform wants is reproducible for real Bedrock billing**: AWS device-code SSO (`aws sso login --use-device-code`), `aws login --remote` for SSO-less users, plus equivalent Vertex (`gcpAuthRefresh`) and Foundry (Entra chain) flows — no static keys in containers, refresh hooks keep long sessions alive.
4. **BYO vs resale is not either/or — the partnership-optimal architecture is hybrid**: BYO customer-account Bedrock consumption (100% EDP burn with discount, Activate-credit eligible, ACE-registrable as "Estimated AWS MRR") plus a transactable AWS Marketplace listing for the platform fee (the only thing that retires AWS sellers' quota and unlocks ISV Accelerate). The documented winners (Writer, Perplexity, Glean) all run this combination.
5. **The operational realities that shape the build**: role-chaining caps BYO sessions at 1h (solved by `awsCredentialExport` vending), fresh-account quota cold-start is the biggest onboarding friction, LiteLLM's cache-token accounting bugs make CUR the only billing truth for resale, and the June-2026 Bedrock data-retention regime (`provider_data_share` required for Fable-5-class models) splits disclosure obligations along BYO/resale lines.

**Top recommendations:**

1. Ship the Phase-0 Bedrock spike now (env-var flag in the existing `claude_code_adapter`; pin models explicitly).
2. Build the provider-connect UI with two AWS tiers — org cross-account role (CloudFormation quick-create + ExternalId) and personal device-flow sign-in — mirroring Kiro's organization/Builder-ID split; extend to Vertex/Foundry on the same `AgentCredential` surface.
3. Start the partnership clock immediately: APN registration → Marketplace listing ("AI Agents and Tools" category) → FTR → register every BYO customer in ACE. ISV Accelerate needs 12 months of pipeline history.
4. Default architecture: direct-from-workspace Bedrock calls with credential-layer quotas (AWS's own blessed shape for Claude Code); add a LiteLLM gateway only for the demand-gated resale tier.
5. Treat prompt-cache health, model pinning, and `max_tokens` governance as day-one operational disciplines — they dominate both cost and quota capacity.

### Table of Contents

1. Technical Research Scope Confirmation
2. Technology Stack Analysis — Bedrock surfaces, CLI landscape matrix, Claude Code deep dive, Kiro disqualification, OSS CLIs, gateway technologies, adoption trends
3. Integration Patterns Analysis — BYO cross-account provisioning, resale metering, wire protocols and gateway contract, fleet provisioning, usage accounting, Marketplace metering, end-user auth flows (AWS/Vertex/Azure), security patterns
4. Architectural Patterns and Design — AWS's two blessed shapes, candidate architectures A–D, tenant isolation, deployment/ops, data architecture and the June-2026 retention regime, partnership alignment
5. Implementation Approaches and Technology Adoption — codebase fit, phased roadmap, workflows, testing, operations, cost optimization, risk register, recommendations and KPIs
6. Research Synthesis (this section) — executive summary, methodology, strategic conclusion, source verification

### Research Introduction and Methodology

**Significance.** The platform's business goal — "users spend tokens in Bedrock through our platform" — sits at the intersection of three 2025–2026 shifts: Anthropic's enforcement wave that made cloud-provider billing the only durable third-party channel for Claude-powered products; AWS's buildout of Bedrock into a first-class Anthropic surface (Mantle endpoint, Bedrock API keys, data-retention modes, IAM-principal cost allocation); and AWS's partner economics that reward ISVs who either drive customer consumption or transact through Marketplace. Getting the integration architecture right therefore determines not just engineering cost but the ceiling of the AWS relationship.

**Methodology.** Six-step BMAD technical-research workflow (scope → stack → integration → architecture → implementation → synthesis), executed 2026-07-24 with ten parallel web-research agents plus direct codebase inspection. All claims verified against live primary sources (code.claude.com, docs.aws.amazon.com, platform.claude.com, kiro.dev, opencode.ai, GitHub issues/repos, AWS/APN blogs) with confidence levels (High/Medium/Low) attached to every non-trivial claim; conflicting sources surfaced explicitly (e.g., Mantle quota discrepancy, MACC eligibility). Training-data-only claims are flagged as such.

**Goals → outcomes.**
- *Compare Bedrock-capable CLIs* → full support matrix with per-tool config, auth, caching, license, and fit verdicts (step 2).
- *Evaluate BYO vs resale* → complete integration mechanics for both (step 3) and candidate architectures A–D with trade-off table (step 4).
- *Identify what makes consumption count for AWS partnership* → the formal ladder (ACE/FTR/ISV Accelerate/Marketplace), the quota-retirement asymmetry, EDP mechanics, and the documented hybrid winning pattern (step 4).
- *Recommend a path maximizing Bedrock consumption* → phased roadmap grounded in the actual codebase seams (step 5), synthesized above.
- *Discovered along the way*: the multi-cloud self-serve auth-flow design (user request mid-research), the June-2026 data-retention regime, and Coder's own AWS Strategic Collaboration Agreement.

### Strategic Conclusion

The platform should **not** chase an "Amazon CLI" — Amazon's own CLI is commercially closed to this use case. Instead, the sanctioned, lowest-friction, partnership-maximizing path is to make the platform the best place to run **Claude Code on the customer's own Bedrock**, wrap it in the Kiro-grade self-serve connect UX (which Kiro itself cannot offer for Bedrock), register every connected account as AWS co-sell pipeline, and transact the platform fee through Marketplace. Resale of tokens is a later, demand-gated monetization tier — not the foundation. This positions Amazon as a distribution channel (AMs with a consumption story and a quota event), Anthropic as a compliant vendor relationship (CPN-eligible), and the platform as multi-cloud by design (Vertex/Foundry flows on the same surface).

**Open items to verify before build/marketing commitments:** exact Mantle workspace header name (`anthropic-workspace` vs `anthropic-workspace-id`), MACC eligibility of Claude-in-Foundry, Reserved-tier $/TPM pricing (account team), `aws login --remote` terminal UX, and the current fix-state of pinned LiteLLM/OpenCode caching issues.

### Source Verification and Research Quality

- **Primary sources**: official documentation fetched live 2026-07-24 — code.claude.com/docs (Bedrock, Vertex, Foundry, gateway protocol, settings, monitoring, legal), docs.aws.amazon.com (Bedrock user guide: API keys, quotas, CRIS, data retention, projects, marketplace metering; IAM/STS; CloudFormation), platform.claude.com (Claude in Amazon Bedrock, models), kiro.dev (docs/pricing/FAQ), opencode.ai, goose-docs.ai, aider.chat, docs.litellm.ai, aws.amazon.com/partners + APN blog, AWS Well-Architected Generative AI Lens.
- **Secondary sources**: GitHub issues/PRs (LiteLLM, OpenCode, Kiro, Claude Code, Goose), AWS Builder/re:Post articles, practitioner guides (Tackle, Labra, Suger, CloudZero, Caylent, TrueFoundry — vendor bias flagged where relevant), press coverage.
- **Quality controls**: multi-source validation for critical claims; confidence levels throughout; explicit conflict notes; training-data-only claims flagged (gcloud/az headless UX details, some lifetimes); absence-of-evidence findings marked (no public SaaS Bedrock topologies; no formal "ISV-driven consumption" program).
- **Limitations**: quota values are account-specific and shift; LiteLLM bug fix-states move weekly; partner-program terms (EDP caps, Reserved pricing) are contractual and partly non-public; one research agent was interrupted by a spend limit and resumed — its az/gcloud specifics carry Medium confidence.

---

**Technical Research Completion Date:** 2026-07-24
**Source Verification:** all claims cited inline with live URLs and confidence levels
**Overall Confidence:** High on integration mechanics and CLI landscape; Medium-High on partnership economics (formal rules High, AM behavior informal)

_This document serves as the authoritative reference for the Bedrock integration decision and the AWS partnership plan._

---

<!-- Content will be appended sequentially through research workflow steps -->
