# frozen_string_literal: true

class GateService
  class << self
    def resolve_github_checks(repo_full_name:, pr_number:, conclusion:)
      gates = Gate
        .pending
        .for_repository(repo_full_name)
        .for_repo_full_name(repo_full_name)
        .for_github_pr_number(pr_number)

      gates.find_each do |gate|
        TaskService.resolve_gate(
          gate: gate,
          resolution_data: { conclusion: conclusion }
        )
      end
    end

    def resolve_github_workflow(repo_full_name:, run_id:, conclusion:)
      gates = Gate
        .pending
        .for_repository(repo_full_name)
        .for_repo_full_name(repo_full_name)
        .for_github_workflow_run_id(run_id)

      gates.find_each do |gate|
        TaskService.resolve_gate(
          gate: gate,
          resolution_data: { conclusion: conclusion }
        )
      end
    end

    def resolve_gitlab_pipeline(repo_full_name:, pipeline_id:, status:, mr_iid: nil)
      gates = Gate
        .pending
        .for_repository(repo_full_name)
        .for_repo_full_name(repo_full_name)
        .for_gitlab_pipeline_id(pipeline_id)

      gates.find_each do |gate|
        TaskService.resolve_gate(
          gate: gate,
          resolution_data: { status: status }
        )
      end
    end
  end
end
