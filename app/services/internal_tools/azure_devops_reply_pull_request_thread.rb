# frozen_string_literal: true

module InternalTools
  class AzureDevopsReplyPullRequestThread < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Reply To Pull Request Thread"
      description "Reply inside an existing review conversation on an Azure Repos pull request. `thread_id` comes from azure_devops_list_pull_request_threads; replying by comment id is not possible in Azure. `operation_key` is required and makes the call replay-safe. Returns the posted comment as JSON."
      tags :azure_devops
      requires_integration :azure_devops
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
      param :thread_id, type: :integer, description: "Thread to reply in.", required: true
      param :content, type: :string, description: "Reply text (markdown).", required: true
      param :operation_key, type: :string, description: "Caller-chosen idempotency key. Reuse it verbatim when retrying.", required: true
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        payload = { repository_id: repository.id, pull_request_id: params[:pull_request_id],
                    thread_id: params[:thread_id], content: params[:content] }

        with_operation(integration, "reply_pull_request_thread", payload) do
          AzureDevops::PullRequestService.new(integration).reply_to_thread(
            repository, params[:pull_request_id], params[:thread_id], content: params[:content]
          )
        end
      end
    end
  end
end
