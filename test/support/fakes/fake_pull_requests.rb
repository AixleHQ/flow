# frozen_string_literal: true

module Fakes
  # In-memory pull-request host implementing the PullRequests::Provider port —
  # the canonical fake for the pull_request_* tools (testing doctrine R3).
  # `stub_pull_requests!` installs it behind `PullRequests::Provider.for`.
  #
  # Kept honest by test/services/pull_requests/fake_pull_requests_contract_test.rb,
  # which runs PullRequestsProviderContract — the same assertions the GitLab
  # adapter satisfies against WebMock'd GitLab payloads (R4).
  class FakePullRequests < PullRequests::Provider
    Call = Struct.new(:name, :args, keyword_init: true)

    # The port's value classes, by the names the real adapters use for them.
    Page = PullRequests::Page
    PullRequest = PullRequests::PullRequest
    Comment = PullRequests::Comment
    FileChange = PullRequests::FileChange
    Review = PullRequests::Review
    Checks = PullRequests::Checks
    MergeResult = PullRequests::MergeResult
    Error = PullRequests::Error

    attr_reader :calls

    def initialize(integration = nil)
      super
      @pull_requests = {}
      @comments = Hash.new { |hash, key| hash[key] = [] }
      @checks = {}
      @failures = {}
      @calls = []
      @pending_merges = false
    end

    # --- arrangement ---------------------------------------------------------

    def add_pull_request(repository, number: nil, source_branch: "feature", target_branch: "main", title: "Change",
                         state: "open", draft: false, head_sha: SecureRandom.hex(20), mergeable: true)
      number ||= (@pull_requests.keys.select { |repo_id, _| repo_id == repository.id }.map(&:last).max || 0) + 1
      @pull_requests[[ repository.id, number ]] = build(repository, number: number, source_branch: source_branch,
                                                                    target_branch: target_branch, title: title, state: state,
                                                                    draft: draft, head_sha: head_sha, mergeable: mergeable)
    end

    def set_checks(repository, number, state:, items: [])
      @checks[[ repository.id, number ]] = { state: state, items: items }
    end

    # The next call to `method` raises `error` instead of answering.
    def fail_next(method, error)
      @failures[method.to_sym] = error
    end

    # Merges are accepted and not finished, the way an asynchronous host answers.
    def merge_asynchronously!
      @pending_merges = true
    end

    def pull_request(repository, number) = @pull_requests[[ repository.id, number.to_i ]]
    def comments_on(repository, number) = @comments[[ repository.id, number.to_i ]]
    def called?(name) = calls.any? { |call| call.name == name }

    # --- PullRequests::Provider ---------------------------------------------

    def list(repository, state: "open", source_branch: nil, cursor: nil, limit: 20)
      record(:list, repository: repository.id, state: state, source_branch: source_branch)
      items = @pull_requests.values.select { |pr| pr.url.include?("/#{repository.full_name}/") }
      items = items.select { |pr| pr.state == state } unless state == "all"
      items = items.select { |pr| pr.source_branch == source_branch } if source_branch.present?
      offset = cursor.to_i
      Page.new(items: items.drop(offset).first(limit), next_cursor: (items.size > offset + limit ? (offset + limit).to_s : nil))
    end

    def get(repository, ref)
      record(:get, repository: repository.id, ref: ref)
      find!(repository, ref)
    end

    def changes(repository, ref, cursor: nil, limit: 50)
      record(:changes, repository: repository.id, ref: ref)
      find!(repository, ref)
      Page.new(items: [ FileChange.new(path: "app/models/user.rb", old_path: nil, status: "modified", additions: 3, deletions: 1) ],
               next_cursor: nil)
    end

    def create(repository, source_branch:, target_branch:, title:, description: nil, draft: true)
      record(:create, repository: repository.id, source_branch: source_branch, target_branch: target_branch, title: title)
      add_pull_request(repository, source_branch: source_branch, target_branch: target_branch, title: title, draft: draft)
    end

    def update(repository, ref, **attributes)
      record(:update, repository: repository.id, ref: ref, **attributes)
      current = find!(repository, ref)
      if current.merged? && attributes[:state].present?
        raise Error::Conflict.new("Pull request #{current.number} is merged", details: { state: "merged" })
      end

      changed = current.with(**attributes.slice(:title, :description, :target_branch, :draft).compact,
                             state: attributes[:state].presence || current.state)
      @pull_requests[[ repository.id, current.number ]] = changed
    end

    def list_comments(repository, ref, cursor: nil, limit: 50)
      record(:list_comments, repository: repository.id, ref: ref)
      Page.new(items: comments_on(repository, find!(repository, ref).number), next_cursor: nil)
    end

    def add_comment(repository, ref, body:, file_path: nil, line: nil, reply_to: nil)
      record(:add_comment, repository: repository.id, ref: ref, body: body, file_path: file_path, line: line, reply_to: reply_to)
      raise Error.new("line is required with file_path", code: "validation_failed") if file_path.present? && line.blank?

      number = find!(repository, ref).number
      comment = Comment.new(id: SecureRandom.random_number(1_000_000), parent_id: reply_to, author: "aixle-bot",
                            body: body, file_path: file_path, line: line, resolved: nil, created_at: Time.current)
      comments_on(repository, number) << comment
      comment
    end

    def review(repository, ref, verdict:, body: nil)
      record(:review, repository: repository.id, ref: ref, verdict: verdict, body: body)
      find!(repository, ref)
      Review.new(reviewer: "aixle-bot", verdict: verdict.to_s, submitted_at: Time.current)
    end

    def merge(repository, ref, expected_head_sha:, strategy: nil, delete_source_branch: false, message: nil)
      record(:merge_read, repository: repository.id, ref: ref)
      current = find!(repository, ref)
      return MergeResult.new(merged: true, already_merged: true, pending: false, pull_request: current) if current.merged?
      raise Error::Conflict.new("Pull request #{current.number} is closed", details: { state: current.state }) unless current.open?
      unless current.head_sha == expected_head_sha
        raise Error::Conflict.new("Pull request #{current.number} has moved since it was reviewed",
                                  details: { current_head_sha: current.head_sha, expected_head_sha: expected_head_sha })
      end

      record(:merge, repository: repository.id, ref: ref, expected_head_sha: expected_head_sha, strategy: strategy)
      return MergeResult.new(merged: false, already_merged: false, pending: true, pull_request: current) if @pending_merges

      merged = current.with(state: "merged")
      @pull_requests[[ repository.id, current.number ]] = merged
      MergeResult.new(merged: true, already_merged: false, pending: false, pull_request: merged)
    end

    def checks(repository, ref)
      record(:checks, repository: repository.id, ref: ref)
      current = find!(repository, ref)
      arranged = @checks.fetch([ repository.id, current.number ], { state: "none", items: [] })
      Checks.new(state: arranged[:state], head_sha: current.head_sha, items: arranged[:items])
    end

    def owns_reference?(repository, ref)
      ref.to_s.start_with?("#{url_base(repository)}/")
    end

    def url_base(repository) = "https://code.example/#{repository.full_name}/pull"

    private

    def build(repository, number:, source_branch:, target_branch:, title:, state:, draft:, head_sha:, mergeable:)
      PullRequest.new(number: number, url: "#{url_base(repository)}/#{number}", title: title, description: nil,
                      state: state, draft: draft, source_branch: source_branch, target_branch: target_branch,
                      head_sha: head_sha, author: "aixle-bot", reviewers: [], mergeable: mergeable,
                      created_at: Time.current, updated_at: Time.current)
    end

    def find!(repository, ref)
      pull_request(repository, number_of(repository, ref)) ||
        raise(Error.new("No pull request #{ref} in #{repository.full_name}", code: "not_found_or_inaccessible"))
    end

    def record(name, **args)
      @calls << Call.new(name: name, args: args)
      error = @failures.delete(name)
      raise error if error
    end
  end
end

# Installs a FakePullRequests behind the port's factory, the app-owned seam every
# pull_request_* tool resolves its provider through.
module PullRequestsTestHelper
  def stub_pull_requests!(fake = Fakes::FakePullRequests.new)
    PullRequests::Provider.stubs(:for).returns(fake)
    fake
  end
end
