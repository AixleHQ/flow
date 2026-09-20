# Integration provider abstractions — technical design v1

Status: **Draft proposal; for review**
Related: YouTrack integration technical design v6 (`docs/design/youtrack-integration-tech-design-v6.md`)
Date: 2026-09-18

## 1. Purpose and boundaries

The platform already connects six third-party providers (Slack, Coder, GitHub, GitLab, Azure
DevOps, YouTrack). Jira and GitHub Projects are the next two on the roadmap. Each existing
provider was implemented independently, so three layers that every provider must pass through —
connection/credential verification, webhook ingress → trigger dispatch, and MCP tool
integration-resolution — have accumulated provider-named branches inside otherwise generic
files instead of a registrable per-provider unit.

This document proposes three abstraction interfaces, plus a `.descendants`-based discovery
mechanism consistent with the pattern the codebase already uses for `Tools::Registry` and
`WorkflowDuplicator::DependencyCopier`. **Scope of this phase is narrow on purpose:** introduce
the interfaces, and migrate the already-implemented YouTrack integration onto them, proving the
abstraction against a real provider before any other integration adopts it.

This phase does **not** touch Slack, Coder, GitHub, GitLab, or Azure DevOps — they keep their
current, independent code paths unchanged. It does **not** implement Jira or GitHub Projects —
those are separately scoped once the pattern is validated. It does **not** build the
schema-driven frontend trigger-config registry — `TriggerFormPanel.tsx` keeps its current
per-`kind` branching for now.

Note on context: YouTrack is already implemented in the codebase (`Youtrack::IntegrationService`,
`YoutrackContext`, webhook ingress branches, `youtrack_*` tools) — this is a refactor of existing,
working code onto shared interfaces, not new product functionality. Behavior is expected to be
preserved except one explicitly called-out fix (§6.3).

## 2. Decisions

| Area | V1 decision |
|---|---|
| Interfaces introduced | `Integrations::ConnectService` (connection layer), `Webhooks::ProviderAdapter` (ingress → trigger pipeline), `InternalTools::Concerns::IntegrationResolvable` (MCP tool integration-resolution). |
| Providers migrated | YouTrack only. |
| Providers left alone | Slack, Coder, GitHub, GitLab, Azure DevOps — no code changes in this phase. |
| New providers | Jira, GitHub Projects — not built in this phase; explicitly deferred until the pattern is validated on YouTrack. |
| Frontend | `TriggerFormPanel.tsx` schema/registry-driven config — deferred; out of scope. |
| Discovery | Class-based and convention-driven (`.descendants` + a `provider` class attribute), no manually maintained registration list — mirrors `Tools::Registry`'s "writing the class is the registration." |
| Generic call sites | `Integrations::ConnectService` subclasses are invoked directly by controllers (replacing `Youtrack::IntegrationService`, not `Integration` itself). `Webhooks::IngressController`, `Webhooks::ProcessEventJob`, and `TriggerEngine` are changed to resolve a `Webhooks::ProviderAdapter` by provider instead of branching inline — but only the YouTrack code paths move; Slack's existing inline handling is untouched. |
| Behavior parity | Migration must be behavior-preserving, with one explicit, called-out exception: YouTrack's integration-resolution fallthrough on an invalid run-context `integration_id` changes to match Slack's existing fallthrough behavior (§6.3) — flagged for explicit sign-off, not silently folded in. |
| Testing | Follows `docs/testing.md`: never stub the class under test; the three interfaces get a shared contract (a reusable shared-example group per interface) that the YouTrack adapter is tested against now, so a later Slack/Coder migration reuses the same contract instead of re-deriving it. |
| Out of scope | Azure DevOps' deliberately different, stricter tool-context design (explicit `integration_id`, no default-integration selection) is not folded into `IntegrationResolvable` — it stays a documented exception, not a gap to close. |

## 3. Current state and friction

### 3.1 Connection layer

Six `<Provider>::IntegrationService` classes exist with no shared parent
(`app/services/{slack,coder,github,gitlab,azure_devops,youtrack}/integration_service.rb`). Across
them:

- URL normalization (`url.to_s.strip.chomp("/")`) is reimplemented identically in
  `Coder::IntegrationService` and `Youtrack::IntegrationService`.
- The `begin verify; rescue ConfigurationError/AuthenticationError; status = :error` skeleton is
  repeated near-verbatim in Coder/GitHub/GitLab/Azure DevOps/YouTrack, each redefining its own
  exception classes rather than sharing one hierarchy.
- "Build integration, set `credentials_data`, set a name with an `(unverified)` fallback suffix"
  is copy-pasted across all five non-Slack services.
- Error persistence uses four different names for the same concept
  (`save_error`/`record_error`/inline rescue) across Slack/Azure/others.
- `Integration` (`app/models/integration.rb`) accretes per-provider accessor clusters directly on
  the model, each under a comment-header section (e.g. `# ----- Azure DevOps accessors -----`),
  plus three provider-specific class-level finder methods
  (`find_or_build_gitlab_for_token`, `find_or_build_github_for_pat`,
  `find_or_build_github_for_installation`).

### 3.2 Webhook ingress → trigger pipeline

This is the most spread-out layer:

- The "generic" `Webhooks::IngressController#receive` already contains YouTrack-specific inline
  logic in two places: a `normalize_youtrack_ingress` method (filtering event types, truncating
  text, checking `TriggerBinding` existence, mutating `integration.settings`), and a
  `case endpoint.provider.to_s when "slack" / "youtrack" / else` inside `idempotency_key_for`.
- `Webhooks::ProcessEventJob#normalize` is a `case endpoint.provider.to_s when "slack" /
  "youtrack" / else normalize_generic`, with three separate inlined private methods and no
  normalizer class/interface.
- `TriggerEngine#fire_workflow` hardcodes
  `slack_run_context(event).merge(youtrack_run_context(event, subject))` — a hand-wired call
  chain, not a dispatch table. `TriggerEngine#dispatch` additionally has a YouTrack-only
  `where(integration_id: ...) if event.event_type.start_with?("youtrack.")` branch.
- `TriggerBinding` carries a YouTrack-named validation method
  (`youtrack_integration_is_visible`) instead of a generic "this event type requires a visible
  integration" hook.
- A usable interface shape already exists elsewhere in the codebase for a related problem —
  `app/services/context_builders/base.rb` (`applicable?` / `build` / `section`) — but it has not
  been reused for webhook run-context construction; that logic lives ad hoc inside
  `TriggerEngine` instead.

Net effect: adding a provider to this layer today means touching `WebhookEndpoint`'s enum, the
ingress controller (or a new dedicated one), `ProcessEventJob`'s case/when, `TriggerEngine` (new
`*_run_context` method **and** editing the hardcoded merge call **and** the `dispatch` branch),
and `TriggerBinding`'s validation — five-plus files with real branching logic, not registration.

### 3.3 MCP integration-resolution

Three tool concerns (`SlackContext`, `YoutrackContext`, `CoderResolver`) each hand-copy the same
query: resolve the integration to use for a run by trying
`workflow_run.shared_context[provider]["integration_id"]` first, then falling back to
`Integration.active.where(provider:, company_id:).where("project_id = :pid OR project_id IS
NULL", ...).order(Arel.sql("project_id IS NULL")).first`. `CoderResolver`'s own comment says it
"mirrors SlackPostMessage#slack_integration" — the pattern is copy-derived by hand, not shared.
The three copies have already diverged: `SlackContext` falls through to the project/company scan
when the run-context id doesn't resolve; `YoutrackContext` returns `nil` outright in that case.
`requires_integration :provider` (the `Tools::DefinitionDSL` macro) only gates tool
*visibility* — it does not resolve which integration row to use, so this duplication is not
accidental, it is the only place that logic lives today.

`AzureDevopsContext` is deliberately different by design — it rejects "first active integration"
defaulting and requires an explicit `integration_id` (or derives one from an attached
repository), with its own ownership re-verification and idempotent operation ledger. This is a
documented, intentional exception, not a fourth copy of the same bug.

### 3.4 What is already generic — not in scope to change

- `Tools::Registry` builds the tool list via `.descendants` + presence of a `tool do...end`
  block — no manifest to maintain. New `youtrack_*`/future `jira_*` tool classes self-register.
- `WorkflowDuplicator::DependencyCopier#copy_tool` branches on `tool.platform_tool?` /
  `tool.requires_integration`, never on provider name — workflow duplication needs no change for
  any new provider.
- `Web::Company::Projects::IntegrationsPolicy` is a single shared policy; scoping is handled by
  `Integration`'s `company_wide`/`visible_for_project` scopes.

These three are the target shape for the layers in §3.1–§3.3, and are cited here as the pattern
to match, not as work items.

## 4. Proposed abstractions

### 4.1 `Integrations::ConnectService`

A template-method base class:

```ruby
module Integrations
  class ConnectService
    def initialize(company:, project: nil, connected_by:, params:)
      # ...
    end

    def call
      integration = build_integration
      integration.credentials_data = credentials(params)
      integration.settings = settings(params)
      begin
        verify!(integration)
        integration.status = :active
      rescue Integrations::VerificationError => e
        integration.status = :error
        integration.settings["error"] = sanitize(e.message)
      end
      integration.save!
      integration
    end

    private

    def provider = raise NotImplementedError
    def credentials(params) = raise NotImplementedError
    def settings(params) = raise NotImplementedError
    def verify!(integration) = raise NotImplementedError
  end
end
```

`Integrations::UrlNormalizer` (the existing `strip.chomp("/")` rule, extracted once) and a single
`Integrations::VerificationError` hierarchy are shared utilities the subclass hooks use. A
subclass implements only `provider`, `credentials`, `settings`, and `verify!` — everything else
(status transition, error persistence, the `(unverified)` naming fallback) is inherited.

This phase adds the base class and one subclass, `Youtrack::ConnectService`, replacing
`Youtrack::IntegrationService`'s hand-rolled version of the same skeleton. No other
`<Provider>::IntegrationService` is refactored to inherit from it in this phase.

### 4.2 `Webhooks::ProviderAdapter`

An interface covering the full ingress → trigger pipeline for one provider:

```ruby
module Webhooks
  class ProviderAdapter
    class << self
      attr_accessor :provider
    end

    def verification_strategy = raise NotImplementedError   # :shared_token, :hmac_sha256, ...
    def classify(raw_payload) = raise NotImplementedError    # -> event_type | :unsupported
    def redact(raw_payload, event_type) = raise NotImplementedError  # -> bounded hash for ReceivedWebhook
    def dedup_key(event_type, redacted) = raise NotImplementedError
    def normalize(received_webhook) = raise NotImplementedError      # -> {event_type:, subject:, data:}
    def run_context(event, subject) = raise NotImplementedError      # -> hash merged into shared_context
    def requires_integration? = true
  end
end
```

`Webhooks::AdapterRegistry` discovers adapters via `.descendants` keyed by `.provider`, the same
convention `Tools::Registry` already uses. Call sites change only insofar as they add a
YouTrack-shaped path through the adapter instead of a literal `"youtrack"` branch:

- `Webhooks::IngressController#receive` calls `adapter.classify` / `adapter.redact` /
  `adapter.dedup_key` for YouTrack instead of `normalize_youtrack_ingress` and the `"youtrack"`
  arm of `idempotency_key_for`'s case statement. Slack's existing inline path in the same
  controller is left as-is.
- `Webhooks::ProcessEventJob#normalize` calls `adapter.normalize(received_webhook)` for YouTrack
  instead of the private `normalize_youtrack` method; the `"slack"` and `else` arms are untouched.
- `TriggerEngine#fire_workflow` resolves the adapter for the event's provider and calls
  `adapter.run_context(event, subject)`, replacing the hardcoded `youtrack_run_context` call and
  its place in the merge chain; `slack_run_context` keeps being called directly, unchanged.
- `TriggerBinding`'s YouTrack-named validation is generalized to check
  `adapter.requires_integration?` for the binding's event type rather than being named after the
  provider — this one change is provider-agnostic by construction and does not need a follow-up
  when Jira/GitHub Projects land.

### 4.3 `InternalTools::Concerns::IntegrationResolvable`

```ruby
module InternalTools
  module Concerns
    module IntegrationResolvable
      extend ActiveSupport::Concern

      class_methods do
        def resolves_integration_for(provider)
          define_method(:"#{provider}_integration") { resolve_integration(provider) }
        end
      end

      private

      def resolve_integration(provider)
        return if project.nil?

        scope = Integration.active.where(provider: provider, company_id: project.company_id)
        ctx = workflow_run.shared_context[provider.to_s] || {}
        if (id = ctx["integration_id"]).present? && (found = scope.find_by(id: id))
          return found
        end

        scope.where("project_id = :pid OR project_id IS NULL", pid: project.id)
             .order(Arel.sql("project_id IS NULL"), :id)
             .first
      end
    end
  end
end
```

`YoutrackContext` includes this concern and drops its hand-copied version of the query, keeping
only genuinely YouTrack-domain logic. `SlackContext` and `CoderResolver` are **not** changed in
this phase — they keep their current, independently-working copies. `AzureDevopsContext` is
explicitly excluded by design (§3.3) and is never a candidate for this concern.

## 5. YouTrack migration

| Current | Becomes |
|---|---|
| `Youtrack::IntegrationService` | `Youtrack::ConnectService < Integrations::ConnectService` |
| `normalize_youtrack_ingress` (in `IngressController`) + YouTrack arm of `idempotency_key_for` | `Youtrack::WebhookAdapter#classify` / `#redact` / `#dedup_key` |
| `normalize_youtrack` (in `ProcessEventJob`) | `Youtrack::WebhookAdapter#normalize` |
| `youtrack_run_context` (in `TriggerEngine`) | `Youtrack::WebhookAdapter#run_context` |
| `youtrack_integration_is_visible` (in `TriggerBinding`) | generic `requires_integration?`-driven check (§4.2) |
| `YoutrackContext`'s hand-copied resolution query | `include InternalTools::Concerns::IntegrationResolvable; resolves_integration_for :youtrack` |

This is a pure refactor of already-shipped code, not new functionality. Existing YouTrack fixture
coverage (dedup, redaction bounds, subject resolution, project-scope enforcement) is reused
against the new classes rather than rewritten from scratch; only the resolution-fallthrough
change in §6.3 needs a new/updated case.

## 6. Non-goals and explicit exclusions

- Slack, Coder, GitHub, GitLab, and Azure DevOps are not migrated to any of the three interfaces
  in this phase. Their code is left exactly as-is.
- Jira and GitHub Projects are not implemented in this phase. This document only establishes the
  pattern; each new provider is separately scoped once YouTrack's migration is reviewed.
- `TriggerFormPanel.tsx`'s per-`kind` frontend branching is not replaced with a schema/registry.
  It keeps its current shape; YouTrack's existing `kind === 'youtrack'` blocks are untouched.
- `SignatureVerifier`'s `case` on `verification_strategy` is not restructured — a genuinely new
  verification scheme still needs a `when` branch there; this is judged low-frequency enough
  (cryptographic scheme, not per-provider) not to need its own abstraction.
- `Integration` model's per-provider accessor clusters and class-level finder methods are not
  extracted into per-provider settings value objects in this phase — flagged as a candidate for a
  later pass if it keeps growing, not addressed here.

### 6.3 Called-out behavior change

`YoutrackContext#youtrack_integration` currently returns `nil` when the run-context
`integration_id` is present but does not resolve to an active integration (no fallthrough to the
project/company scan). `SlackContext#slack_integration` already falls through in that case. Moving
YouTrack onto the shared `IntegrationResolvable` concern (§4.3) adopts Slack's existing
fallthrough behavior for YouTrack. This is a deliberate, minor behavior change to YouTrack's
runtime tool-resolution (a stale/deleted run-context integration id no longer hard-fails tool
resolution; it falls back to the normal project/company selection) — called out here for explicit
sign-off rather than folded silently into the refactor.

## 7. Risks and open questions

- **Interface granularity risk:** `Webhooks::ProviderAdapter` is sized against one real provider
  (YouTrack). Its shape may need adjustment once a second provider (Jira) is built against it —
  this phase does not guarantee the interface is final, only that it removes YouTrack's current
  duplication.
- **Contract testing:** each interface should ship with a reusable shared-example group
  (`it_behaves_like "a webhook provider adapter"`, etc.) exercised by the YouTrack
  implementation now, per `docs/testing.md`'s mocking rules, so a later Slack/Coder migration
  can adopt the same contract without re-deriving it.
- **Scope creep:** because YouTrack's existing code already touches five-plus files (§3.2), the
  migration PR will look large relative to "just add abstractions." Recommend reviewing it as a
  pure refactor (behavior-preserving except §6.3) rather than as new functionality.

## 8. Acceptance criteria

Migration is complete when: `Integrations::ConnectService`, `Webhooks::ProviderAdapter`, and
`InternalTools::Concerns::IntegrationResolvable` exist with the shared contract tests described
in §7; YouTrack's connect flow, webhook ingress/normalization/dedup, trigger run-context, and MCP
tool integration-resolution all run through these three interfaces instead of provider-named
branches in `IngressController`, `ProcessEventJob`, `TriggerEngine`, `TriggerBinding`, and
`YoutrackContext`; existing YouTrack test coverage passes against the new classes with no
behavior change other than §6.3; and Slack, Coder, GitHub, GitLab, and Azure DevOps have zero
diff.
