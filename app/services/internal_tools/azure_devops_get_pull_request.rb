# frozen_string_literal: true

module InternalTools
  class AzureDevopsGetPullRequest < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Get Pull Request"
      description "Read one Azure Repos pull request in full: description, source/target refs, author, draft and merge state, reviewers and linked work items. The list tool truncates descriptions; this one does not. Returns JSON."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        result = AzureDevops::PullRequestService.new(integration).get(repository, params[:pull_request_id])
        success(result.to_json)
      end
    end
  end
end
