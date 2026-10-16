# frozen_string_literal: true

module InternalTools
  class PullRequestUpdate < Base
    include Concerns::PullRequestContext

    tool do
      display_name "Pull Requests: Update"
      description "Change a pull request's title, description, target branch or draft flag, or close or reopen " \
                  "it. Only the fields you pass change. Returns JSON: {repository_id, pull_request}."
      tags :pull_requests
      inject_when :pull_request_repositories_attached
      user_attachable false
      requires_integration :pull_requests
      unavailable_message Concerns::PullRequestContext::UNAVAILABLE
      idempotent
      param :repository_id, type: :integer, description: Concerns::PullRequestContext::REPOSITORY_PARAM
      param :pull_request, type: :string, required: true, description: Concerns::PullRequestContext::PULL_REQUEST_PARAM
      param :title, type: :string, description: "New title."
      param :description, type: :string, description: "New description (Markdown)."
      param :target_branch, type: :string, description: "New target branch."
      param :draft, type: :boolean, description: "Mark as draft (true) or ready for review (false)."
      param :state, type: :string, enum: %w[open closed], description: "Close or reopen the pull request."
    end

    def execute
      pull_request_guard do
        repository, provider = resolve_target!
        attributes = params.slice(:title, :description, :target_branch, :state).compact_blank.symbolize_keys
        attributes[:draft] = params[:draft] unless params[:draft].nil?
        raise PullRequests::Error.new("Nothing to change", code: "validation_failed") if attributes.empty?

        respond({ repository_id: repository.id, pull_request: provider.update(repository, params[:pull_request], **attributes) })
      end
    end
  end
end
