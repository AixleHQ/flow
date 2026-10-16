# frozen_string_literal: true

module InternalTools
  # Opens a pull request, or answers the one already open for the same source
  # and target: an agent retrying after a timeout should get the pull request it
  # made, not a second one.
  class PullRequestCreate < Base
    include Concerns::PullRequestContext

    tool do
      display_name "Pull Requests: Create"
      description "Open a pull request (GitLab merge request) from a branch you pushed. Opens as a draft unless " \
                  "`draft` is false. If one is already open from the same source to the same target, returns it " \
                  "with `existing: true` instead of opening a second. In a run started from a tracker issue the " \
                  "title is prefixed with the issue key (`ENG-123: …`) unless it already contains it, which is how " \
                  "Jira and the code host link the pull request to the issue. Returns JSON: {pull_request, " \
                  "existing, operation_key}."
      tags :pull_requests
      inject_when :pull_request_repositories_attached
      user_attachable false
      requires_integration :pull_requests
      unavailable_message Concerns::PullRequestContext::UNAVAILABLE
      param :repository_id, type: :integer, description: Concerns::PullRequestContext::REPOSITORY_PARAM
      param :source_branch, type: :string, required: true, description: "The branch with your changes, already pushed."
      param :target_branch, type: :string,
                            description: "The branch to merge into. Defaults to the repository's branch in this " \
                                         "session (the Branch column of the repositories table)."
      param :title, type: :string, required: true, description: "Pull request title."
      param :description, type: :string, description: "Pull request description (Markdown)."
      param :draft, type: :boolean, default: true, description: "Open as a draft."
      param :operation_key, type: :string, description: Concerns::PullRequestContext::OPERATION_KEY_PARAM
    end

    def execute
      pull_request_guard do
        repository, provider = resolve_target!(ref: nil)
        target = params[:target_branch].presence || repository.source_branch
        source = params[:source_branch].to_s.strip
        raise PullRequests::Error.new("source_branch and target_branch are the same", code: "validation_failed") if source == target

        title = keyed_title(params[:title].to_s.strip)
        payload = { repository_id: repository.id, source_branch: source, target_branch: target, title: title }
        with_write(repository, "create", payload) do
          existing = open_pull_request(provider, repository, source, target)
          next { pull_request: existing, existing: true } if existing

          pull_request = provider.create(repository, source_branch: source, target_branch: target, title: title,
                                                     description: params[:description], draft: params[:draft] != false)
          { pull_request: pull_request, existing: false }
        end
      end
    end

    private

    def keyed_title(title)
      key = tracker_issue_key
      return title if key.blank? || title.downcase.include?(key.downcase)

      "#{key}: #{title}"
    end

    def open_pull_request(provider, repository, source, target)
      provider.list(repository, state: "open", source_branch: source, cursor: nil, limit: 100)
              .items.find { |pr| pr.target_branch == target }
    end
  end
end
