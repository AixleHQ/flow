# frozen_string_literal: true

module InternalTools
  class AzureDevopsCreatePullRequestThread < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Create Pull Request Thread"
      description "Start a new review conversation on an Azure Repos pull request. Omit `file_path` for a general comment; supply `file_path` and `right_line` for an inline one. Line numbers are interpreted against the pull request iteration, so pass the `iteration` you read the changes at — coordinates from a different iteration anchor the comment to unrelated code. `operation_key` is required and makes the call replay-safe."
      tags :azure_devops
      requires_integration :azure_devops
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
      param :content, type: :string, description: "Comment text (markdown).", required: true
      param :file_path, type: :string, description: "Repository path for an inline comment, e.g. /app/models/user.rb."
      param :right_line, type: :integer, description: "Line number on the right (new) side, for an inline comment."
      param :iteration, type: :integer, description: "Iteration the line numbers belong to. Defaults to the latest."
      param :operation_key, type: :string, description: "Caller-chosen idempotency key. Reuse it verbatim when retrying.", required: true
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        if params[:right_line].present? && params[:file_path].blank?
          return error({ error: "validation_failed", message: "right_line needs file_path" }.to_json)
        end

        payload = {
          repository_id: repository.id, pull_request_id: params[:pull_request_id],
          content: params[:content], file_path: params[:file_path], right_line: params[:right_line]
        }.compact

        with_operation(integration, "create_pull_request_thread", payload) do
          AzureDevops::PullRequestService.new(integration).create_thread(
            repository, params[:pull_request_id],
            content: params[:content], file_path: params[:file_path],
            right_line: params[:right_line], iteration: params[:iteration]
          )
        end
      end
    end
  end
end
