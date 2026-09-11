# frozen_string_literal: true

module InternalTools
  # The question "may this pull request be completed?", which a build result
  # cannot answer: a policy set can also require reviewers, linked work items and
  # resolved comments.
  class AzureDevopsGetPullRequestPolicies < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Get Pull Request Policies"
      description "Read the branch-policy evaluations for an Azure Repos pull request — what is still blocking it from completing. A green build is NOT merge eligibility: policies can also require reviewers, linked work items or resolved comments. Returns JSON: {evaluations: [{type, status, blocking}], all_blocking_satisfied, blocking_count, unsatisfied}. Check `all_blocking_satisfied` before attempting completion."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        result = AzureDevops::BuildService.new(integration)
                                          .policy_evaluations(repository, params[:pull_request_id])
        success(result.to_json)
      end
    end
  end
end
