# frozen_string_literal: true

module InternalTools
  # Draft by default. An agent opening a review-ready pull request fires branch
  # policies, notifies reviewers and can start an auto-complete — all of which
  # should be a deliberate choice, not the default of a tool call.
  class AzureDevopsCreatePullRequest < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Create Pull Request"
      description "Open a pull request in an attached Azure Repos repository. Push the source branch first — Azure rejects a PR whose source ref does not exist. Created as a DRAFT unless `draft` is explicitly false. `operation_key` is required and makes the call replay-safe: the same key returns the original result instead of opening a second pull request. Returns JSON: {id, title, url, source_branch, target_branch, is_draft}."
      tags :azure_devops
      requires_integration :azure_devops
      destructive false
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :source_branch, type: :string, description: "Branch with the changes (e.g. feature/123).", required: true
      param :target_branch, type: :string, description: "Branch to merge into. Defaults to the repository's configured source branch."
      param :title, type: :string, description: "Pull request title.", required: true
      param :description, type: :string, description: "Pull request body (markdown)."
      param :draft, type: :boolean, description: "Open as a draft. Defaults to true.", default: true
      param :operation_key, type: :string, description: "Caller-chosen idempotency key. Reuse it verbatim when retrying.", required: true
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        target = params[:target_branch].presence || repository.source_branch
        payload = {
          repository_id: repository.id, source_branch: params[:source_branch],
          target_branch: target, title: params[:title], description: params[:description].to_s,
          draft: params[:draft] != false
        }

        with_operation(integration, "create_pull_request", payload) do
          AzureDevops::PullRequestService.new(integration).create(
            repository,
            source_branch: params[:source_branch], target_branch: target,
            title: params[:title], description: params[:description], draft: params[:draft] != false
          )
        end
      end
    end
  end
end
