# frozen_string_literal: true

module Bitbucket
  # The reconciliation side of `bitbucket_pr_statuses_completed` gates: whether
  # every CI status on a pull request's head commit has finished, in the
  # vocabulary Ci::ProbeResult speaks (docs/design/bitbucket-integration.md §8).
  #
  # Commit statuses, not a pipeline: Bitbucket sends no pipeline-finished event,
  # and statuses also carry CI that runs outside Bitbucket Pipelines.
  class CheckStatusService
    FINISHED = %w[SUCCESSFUL FAILED STOPPED].freeze

    def initialize(integration)
      @integration = integration
    end

    def pull_request_statuses(repository, pull_request_id, expected_commit: nil)
      api = Api.for(@integration)
      workspace = repository.external_organization_id
      pr = api.pull_request(workspace, repository.external_id, pull_request_id)
      head = pr[:source_commit].to_s

      if expected_commit.present? && head.present? && !Identifiers.same_commit?(head, expected_commit)
        return Ci::ProbeResult.in_progress("pull request #{pull_request_id} has moved to #{head}")
      end

      statuses = api.commit_statuses(workspace, repository.external_id, head)
      return Ci::ProbeResult.in_progress("no CI status reported yet on #{head.first(12)}") if statuses.empty?

      running = statuses.reject { |status| FINISHED.include?(status[:state]) }
      if running.any?
        return Ci::ProbeResult.in_progress("#{running.size}/#{statuses.size} statuses still running on #{head.first(12)}")
      end

      verdict = statuses.all? { |status| status[:state] == "SUCCESSFUL" } ? "successful" : "failed"
      Ci::ProbeResult.completed(verdict, "#{statuses.size} status(es) finished on pull request #{pull_request_id}")
    rescue Error::NotFound
      Ci::ProbeResult.unresolvable("pull request #{pull_request_id} no longer exists or is not visible to this connection")
    rescue Error => e
      Ci::ProbeResult.unavailable(e.code)
    end
  end
end
