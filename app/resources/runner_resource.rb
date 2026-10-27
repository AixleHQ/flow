# frozen_string_literal: true

# A runner as the runners pages see it. `config` holds only what the runner
# sets; defaults come from the type's schema (Runners::ConfigSchema), which the
# page receives alongside.
class RunnerResource < ApplicationResource
  attributes :id, :name, :project_id, :integration_id, :max_concurrency, :max_environments,
             :status_reason, :last_seen_at, :disabled_at, :revoked_at, :created_at, :updated_at

  # The column is `runner_type` so Rails does not read it as STI; the field is
  # `type` everywhere else (DESIGN.md §2.1).
  typelize %w[manual coder kubernetes]
  attribute :type do |runner|
    runner.runner_type.to_s
  end

  typelize %w[pending connected degraded unreachable disabled revoked]
  attribute :status do |runner|
    runner.status.to_s
  end

  typelize %w[reuse fresh]
  attribute :reuse_policy do |runner|
    runner.reuse_policy.to_s
  end

  typelize %w[company project]
  attribute :scope do |runner|
    runner.project_id.present? ? "project" : "company"
  end

  # Its keys are §2.7's names at every depth, and the form writes them back as
  # they are, so none of them is camelized.
  preserve_keys :config
  typelize "Record<string, unknown>"
  attribute :config do |runner|
    DeepKeyCamelizer.verbatim(runner.config.to_h)
  end

  typelize "{ provisionable: boolean; rebuildable: boolean }"
  attribute :capabilities do |runner|
    runner.capabilities
  end

  typelize "string | null"
  attribute :created_by_name do |runner|
    runner.created_by&.name
  end
end
