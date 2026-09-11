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

    # Azure gates route on the repository GUID, never on `full_name`: that is a
    # display value two organizations can share and a rename changes, so
    # `for_repository` would fan one organization's build out to another's board.
    #
    # `commit` is checked against what the gate was created for. A verdict about
    # a different commit is not evidence about this gate — the branch moved on,
    # and the answer belongs to code nobody is waiting for.
    def resolve_azure_devops_build(external_repository_id:, build_id:, result:, commit: nil)
      gates = Gate.pending
                  .for_azure_repository(external_repository_id)
                  .for_azure_build_id(build_id)

      gates.find_each do |gate|
        next if mismatched_commit?(gate, commit)

        TaskService.resolve_gate(gate: gate, resolution_data: { conclusion: result, commit: commit }.compact)
      end
    end

    # Branch policies, not a build result: a green build is not merge
    # eligibility, because a policy set can also require reviewers, linked work
    # items or resolved comments.
    def resolve_azure_devops_pr_policies(external_repository_id:, pull_request_id:, satisfied:,
                                         commit: nil, unsatisfied: [])
      gates = Gate.pending
                  .for_azure_repository(external_repository_id)
                  .for_azure_pull_request_id(pull_request_id)

      gates.find_each do |gate|
        next if mismatched_commit?(gate, commit)
        # Only a satisfied policy set resolves the gate. "Not approved yet" is
        # the normal in-flight state and must leave it pending.
        next unless satisfied

        TaskService.resolve_gate(
          gate: gate,
          resolution_data: { conclusion: "approved", commit: commit, unsatisfied: unsatisfied.presence }.compact
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

    private

    # A gate created without an expected commit accepts any verdict — that is the
    # pre-existing behaviour for the other providers and is not tightened here.
    def mismatched_commit?(gate, commit)
      expected = gate.expected_commit
      return false if expected.blank? || commit.blank?

      expected != commit
    end
  end
end
