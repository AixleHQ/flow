# frozen_string_literal: true

module Ci
  # Asks the CI provider what happened to the run a gate is waiting on.
  #
  # Everything between "a gate row" and "a provider answer" lives here: finding
  # the repository the gate named, finding the integration that can read it, and
  # picking the adapter call that matches the gate type. Each of those lookups can
  # fail in a way no webhook will ever fix — the repository was detached from the
  # project, the integration was disconnected, the metadata names a repo that is
  # not the project's — and those all come back as `unresolvable` with the reason
  # spelled out, because that is precisely the "invalid repository/run" case that
  # used to wedge a task forever.
  #
  # Returns a `Ci::ProbeResult` and never raises: a probe that cannot decide
  # (`unavailable`) is a normal outcome the sweep retries.
  class GateProbe
    def initialize(gate)
      @gate = gate
    end

    def call
      return ProbeResult.unresolvable("#{gate.gate_type} is not a CI gate type") unless gate.ci?
      # Azure gates name the repository by GUID; the others by display name.
      if gate.provider == "azure_devops"
        return ProbeResult.unresolvable("gate metadata has no external_repository_id") if gate.azure_repository_id.blank?
      elsif repo_full_name.blank?
        return ProbeResult.unresolvable("gate metadata has no repo_full_name")
      end
      return ProbeResult.unresolvable("gate metadata has no #{gate.reference_type}") if gate.reference.blank?

      repository = linked_repository
      if repository.nil?
        return ProbeResult.unresolvable("#{gate_repository_label} is not linked to project ##{project&.id}")
      end

      integration = repository.integration
      if integration.nil?
        return ProbeResult.unresolvable(
          "#{gate_repository_label} is attached without an integration, so its CI is unreadable"
        )
      end
      unless integration.provider.to_s == gate.provider
        return ProbeResult.unresolvable(
          "#{gate_repository_label} is a #{integration.provider} repository but the gate expects #{gate.provider}"
        )
      end
      unless integration.active?
        return ProbeResult.unavailable("#{integration.provider} integration ##{integration.id} is #{integration.status}")
      end

      probe(integration)
    rescue StandardError => e
      # Adapters already translate their own vendor errors; this is the backstop
      # so one malformed gate can never abort the whole sweep.
      Rails.logger.warn("[Ci::GateProbe] gate ##{gate.id} probe failed: #{e.class}: #{e.message}")
      ProbeResult.unavailable("#{e.class}: #{e.message}")
    end

    private

    attr_reader :gate

    def probe(integration)
      case gate.gate_type.to_s
      when "github_checks_completed"
        Github::CheckStatusService.new(integration).pull_request_checks(repo_full_name, gate.reference.to_i)
      when "github_workflow_completed"
        Github::CheckStatusService.new(integration).workflow_run_status(repo_full_name, gate.reference.to_i)
      when "gitlab_pipeline_completed"
        Gitlab::PipelineStatusService.new(integration).pipeline_status(repo_full_name, gate.reference.to_i)
      when "azure_devops_build_completed"
        AzureDevops::CheckStatusService.new(integration)
                                       .build_status(gate.reference, expected_commit: gate.expected_commit)
      when "azure_devops_pr_policies_satisfied"
        AzureDevops::CheckStatusService.new(integration)
                                       .pull_request_policies(linked_repository, gate.reference,
                                                              expected_commit: gate.expected_commit)
      end
    end

    def gate_repository_label
      gate.azure_repository_id.presence || repo_full_name
    end

    def repo_full_name
      @repo_full_name ||= gate.metadata["repo_full_name"].presence
    end

    def linked_repository
      return nil if project.nil?

      @linked_repository ||=
        if gate.provider == "azure_devops"
          Repository.visible_for_project(project).find_by(external_id: gate.azure_repository_id)
        else
          Repository.visible_for_project(project).find_by(full_name: repo_full_name)
        end
    end

    def project
      @project ||= gate.board_task&.board&.project
    end
  end
end
