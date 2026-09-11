# frozen_string_literal: true

module InternalTools
  class AzureDevopsUpdatePullRequest < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Update Pull Request"
      description "Change an Azure Repos pull request's title, description, or draft state. Completing or merging a pull request is a separate operation and is not available here. Returns the updated pull request as JSON."
      tags :azure_devops
      requires_integration :azure_devops
      idempotent
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
      param :title, type: :string, description: "New title."
      param :description, type: :string, description: "New body (markdown)."
      param :draft, type: :boolean, description: "Set or clear draft state."
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        attributes = { title: params[:title], description: params[:description] }
        attributes[:draft] = params[:draft] unless params[:draft].nil?

        result = AzureDevops::PullRequestService.new(integration).update(
          repository, params[:pull_request_id], attributes.compact
        )
        success(result.to_json)
      end
    end
  end
end
