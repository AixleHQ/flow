# frozen_string_literal: true

module Gitlab
  # Read-only adapter over the GitLab pipeline endpoint, the GitLab half of CI
  # gate reconciliation (see `Github::CheckStatusService` for the contract and
  # `GateReconciler` for how the states are used).
  class PipelineStatusService
    # Terminal pipeline statuses — the same set the pipeline webhook resolves a
    # gate on (`Webhooks::GitlabController`), so reconciliation and the happy path
    # agree on what "finished" means.
    TERMINAL_STATUSES = %w[success failed canceled skipped].freeze

    def initialize(integration)
      @integration = integration
    end

    def pipeline_status(repo_full_name, pipeline_id)
      pipeline = client.pipeline(repo_full_name, pipeline_id)
      status = pipeline.status.to_s

      unless TERMINAL_STATUSES.include?(status)
        # `manual` and `scheduled` sit here too: a blocked pipeline is genuinely
        # unfinished, and only its TTL should end the gate's wait.
        return Ci::ProbeResult.in_progress("pipeline #{pipeline_id} is #{status.presence || 'unknown'}")
      end

      Ci::ProbeResult.completed(status, "pipeline #{pipeline_id} finished as #{status}")
    rescue ::Gitlab::Error::NotFound
      Ci::ProbeResult.unresolvable("pipeline #{pipeline_id} not found in #{repo_full_name}")
    rescue ::Gitlab::Error::Error, Gitlab::TokenService::ConfigurationError => e
      Rails.logger.warn("[Gitlab::PipelineStatusService] #{e.class}: #{e.message}")
      Ci::ProbeResult.unavailable("#{e.class}: #{e.message}")
    end

    private

    def client
      @client ||= Gitlab::TokenService.new(@integration).client
    end
  end
end
