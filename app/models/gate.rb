# frozen_string_literal: true

class Gate < ApplicationRecord
  extend Enumerize

  # CI gate types, i.e. every gate whose resolving event comes from a CI provider
  # and can therefore be reconciled against that provider's API.
  CI_GATE_TYPES = %w[github_checks_completed github_workflow_completed gitlab_pipeline_completed].freeze

  # Provider conclusions that mean "the checks passed" — GitHub's `success` /
  # `neutral` / `skipped` and GitLab's `success` / `skipped`. Anything else a
  # provider reports for a COMPLETED run is a failure, including `nil`: a
  # completed run without a conclusion is not evidence of success.
  PASSING_CONCLUSIONS = %w[success neutral skipped].freeze

  # Newest-first entries kept in `reconciliation_log`. A gate is reconciled every
  # few minutes for at most its TTL, so this is enough to see the whole story of
  # a gate that went stale without letting the column grow unbounded.
  RECONCILIATION_LOG_LIMIT = 20

  belongs_to :board_task
  belongs_to :creator, class_name: "User"

  # `stale` is terminal like `resolved`, but explicitly NOT a pass: the provider
  # never reported a conclusion (webhook lost and the run/repo unreadable, or the
  # TTL ran out while the run was still going). It stops blocking the column
  # auto-trigger — a gate nothing can ever resolve would wedge the task forever —
  # and carries `diagnostic_reason` so the board can say why.
  enumerize :gate_type, in: %i[github_checks_completed github_workflow_completed gitlab_pipeline_completed], predicates: true
  enumerize :status, in: %i[pending resolved stale], default: :pending, predicates: true, scope: true

  validates :gate_type, presence: true
  validates :status, presence: true
  validates :expires_at, presence: true

  before_validation :set_expires_at, on: :create

  scope :pending,  -> { where(status: "pending") }
  scope :resolved, -> { where(status: "resolved") }
  scope :stale,    -> { where(status: "stale") }

  # Everything a person may still act on: pending gates plus the stale ones that
  # need attention. Used by the board payload and the delete endpoint.
  scope :unresolved, -> { where(status: %w[pending stale]) }

  scope :ci, -> { where(gate_type: CI_GATE_TYPES) }

  # Pending CI gates the reconciliation sweep should probe: old enough that the
  # webhook has had a fair chance to arrive, and not probed within the same
  # window. Ordered oldest-first so a backlog drains in creation order.
  scope :reconcilable, ->(now = Time.current, grace: Gate.reconcile_grace) {
    cutoff = now - grace
    pending
      .ci
      .where(created_at: ..cutoff)
      .where("last_reconciled_at IS NULL OR last_reconciled_at <= ?", cutoff)
      .order(:created_at)
  }

  # Scope gates by the repo_full_name stored in their metadata JSONB.
  # Apply after for_repository to keep the result set narrow.
  scope :for_repo_full_name, ->(repo_full_name) {
    where("metadata->>'repo_full_name' = ?", repo_full_name)
  }

  # Scope gates by PR number only — used after the query is already scoped to
  # the correct project(s) via for_repository.
  scope :for_github_pr_number, ->(pr_number) {
    where(gate_type: "github_checks_completed")
      .where("(metadata->>'pr_number')::int = ?", pr_number.to_i)
  }

  # Scope gates by workflow run ID only — used after the query is already
  # scoped to the correct project(s) via for_repository.
  scope :for_github_workflow_run_id, ->(run_id) {
    where(gate_type: "github_workflow_completed")
      .where("(metadata->>'run_id')::bigint = ?", run_id.to_i)
  }

  # Scope gates by GitLab pipeline ID only — used after the query is already
  # scoped to the correct project(s) via for_repository.
  scope :for_gitlab_pipeline_id, ->(pipeline_id) {
    where(gate_type: "gitlab_pipeline_completed")
      .where("(metadata->>'pipeline_id')::bigint = ?", pipeline_id.to_i)
  }

  # Scope gates to tasks whose boards belong to projects connected to the given
  # repository. Handles both project-scoped and company-scoped repositories.
  scope :for_repository, ->(repo_full_name) {
    joins(board_task: { board_column: { board: :project } })
      .where(projects: { id: Repository.project_ids_for(repo_full_name) })
  }

  class << self
    # How long a CI gate may stay pending before the sweep gives up on it.
    def ttl
      (Settings.gates&.ttl_hours || 12).to_f.hours
    end

    # How long a gate is left alone before (and between) provider probes. The
    # webhook is the happy path; probing a gate created seconds ago would just
    # race it.
    def reconcile_grace
      (Settings.gates&.reconcile_after_minutes || 10).to_f.minutes
    end

    # Cap on gates probed per sweep, so one cron tick does a bounded number of
    # provider requests. A backlog drains over successive ticks.
    def reconcile_batch_size
      (Settings.gates&.reconcile_batch_size || 100).to_i
    end
  end

  def ci?
    CI_GATE_TYPES.include?(gate_type.to_s)
  end

  def age_seconds(now = Time.current)
    (now - created_at).round
  end

  def expired?(now = Time.current)
    expires_at.present? && expires_at <= now
  end

  # What this gate says about CI, collapsing status + recorded conclusion into the
  # four states the board distinguishes: still waiting, passed, failed, or never
  # determined. `pending` here means exactly "no provider verdict yet".
  def ci_status
    return "stale" if stale?
    return "pending" unless resolved?

    passed? ? "succeeded" : "failed"
  end

  # The provider's verdict, whatever key it arrived under: GitHub reports a
  # `conclusion`, GitLab a pipeline `status`.
  def conclusion
    resolution_data["conclusion"].presence || resolution_data["status"].presence
  end

  def passed?
    resolved? && PASSING_CONCLUSIONS.include?(conclusion.to_s)
  end

  # Where this gate came from, for the board and for agents reading the task:
  # which provider, which repository, and which run/check/pipeline it is waiting
  # on. Everything here is metadata recorded at creation time — the same
  # identifiers the reconciliation sweep probes with.
  def source
    {
      provider: provider,
      repo_full_name: metadata["repo_full_name"],
      reference_type: reference_type,
      reference: reference
    }
  end

  def provider
    case gate_type.to_s
    when "github_checks_completed", "github_workflow_completed" then "github"
    when "gitlab_pipeline_completed" then "gitlab"
    end
  end

  def reference_type
    case gate_type.to_s
    when "github_checks_completed"    then "pr_number"
    when "github_workflow_completed"  then "run_id"
    when "gitlab_pipeline_completed"  then "pipeline_id"
    end
  end

  def reference
    metadata[reference_type]
  end

  # Append one reconciliation outcome to the audit trail and stamp the probe.
  # Called for EVERY probe, including the ones that changed nothing, so a gate
  # that ends up stale carries the evidence for why.
  def record_reconciliation!(outcome:, detail: nil, now: Time.current)
    entry = { "at" => now.utc.iso8601, "outcome" => outcome.to_s }
    entry["detail"] = detail.to_s.truncate(300) if detail.present?

    update!(
      last_reconciled_at: now,
      reconcile_attempts: reconcile_attempts + 1,
      reconciliation_log: ([ entry ] + Array(reconciliation_log)).first(RECONCILIATION_LOG_LIMIT)
    )
  end

  private

  def set_expires_at
    self.expires_at ||= (created_at || Time.current) + self.class.ttl
  end
end
