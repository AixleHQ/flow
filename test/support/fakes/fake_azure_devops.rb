# frozen_string_literal: true

# In-memory fakes for the app-owned Azure DevOps adapters (testing doctrine R3:
# "one canonical fake per boundary", docs/testing.md). Caller tests — tool
# handlers, controllers, jobs — stub the real constants and get these back
# instead of scattering WebMock stubs through feature tests:
#
#   fakes = stub_azure_devops!(integration: @integration)
#   ...
#   assert fakes.pull_requests.called?(:create)
#
# The canned return shapes are the exact shapes the WebMock contract tests in
# test/services/azure_devops/*_test.rb pin the real adapters to (R4). If a real
# parsed shape drifts, those contract tests fail — keep these in lockstep.
#
# What these deliberately do NOT fake: AzureDevops::CredentialProvider and
# AzureDevops::Client. The authorization chain is the thing most of these tests
# are about, so it stays real; only the HTTP-shaped services above it are
# replaced.
module FakeAzureDevops
  # Shared call recording plus the REAL authorization step.
  #
  # `authorize!` runs AzureDevops::CredentialProvider exactly as the real
  # adapters do, which is what keeps the chain these tests are about live: the
  # deployment switch, the connection's status, the company-owned installation,
  # the approved project scope and the capability profile all still decide. Only
  # the HTTP call underneath is replaced. `resolve!` itself makes no request —
  # a token is fetched lazily when a header is built — so this costs nothing.
  module Recorder
    attr_reader :calls

    def record(method, **args)
      @calls ||= []
      @calls << { method: method }.merge(args)
    end

    def authorize!(capability)
      return if @integration.nil?

      AzureDevops::CredentialProvider.resolve!(@integration, capability: capability)
    end

    def called?(method)
      Array(@calls).any? { |c| c[:method] == method }
    end

    def calls_to(method)
      Array(@calls).select { |c| c[:method] == method }
    end

    def last_call
      Array(@calls).last
    end
  end

  # Mirrors AzureDevops::RepositoryService.
  class RepositoryService
    include Recorder

    DEFAULT_REPO = {
      external_id: "11111111-1111-1111-1111-111111111111",
      external_project_id: "22222222-2222-2222-2222-222222222222",
      external_organization_id: "contoso",
      name: "api",
      project_name: "Customer Platform",
      full_name: "azure_devops:contoso/Customer Platform/api",
      default_branch: "main",
      clone_url: "https://dev.azure.com/contoso/Customer%20Platform/_git/api",
      is_private: true,
      description: nil
    }.freeze

    def initialize(integration = nil, repositories: [ DEFAULT_REPO ], branches: %w[main develop], error: nil)
      @integration = integration
      @repositories = repositories
      @branches = branches
      @error = error
      @calls = []
    end

    def list_available
      authorize!(:"repositories.read")
      record(:list_available)
      # The real adapter swallows its own errors and answers [] so the picker
      # still renders; the fake matches that rather than raising.
      @error ? [] : @repositories
    end

    def find_repo(identifier)
      authorize!(:"repositories.read")
      record(:find_repo, identifier: identifier)
      raise @error if @error

      @repositories.find { |r| r[:external_id] == identifier.to_s }
    end

    def list_branches(identifier)
      authorize!(:"repositories.read")
      record(:list_branches, identifier: identifier)
      @error ? [] : @branches
    end

    def configure(repository) = record(:configure, repository: repository)
    def remove(repository) = record(:remove, repository: repository)

    def build_repository(external_id:, scope:, source_branch: nil, purpose: nil)
      authorize!(:"repositories.read")
      record(:build_repository, external_id: external_id, scope: scope, source_branch: source_branch)
      raise @error if @error

      details = @repositories.find { |r| r[:external_id] == external_id.to_s }
      raise AzureDevops::NotFound, "no such repository" if details.nil?

      Repository.new(
        scope: scope, integration: @integration, full_name: details[:full_name],
        clone_url: details[:clone_url], source_branch: source_branch.presence || details[:default_branch],
        is_private: details[:is_private], purpose: purpose,
        external_id: details[:external_id], external_project_id: details[:external_project_id],
        external_organization_id: details[:external_organization_id]
      )
    end
  end

  # Mirrors AzureDevops::PullRequestService.
  class PullRequestService
    include Recorder

    DEFAULT_PR = {
      id: 9, title: "Fix the thing", status: "active", is_draft: true,
      source_branch: "feature/1", target_branch: "main", author: "Aixle",
      merge_status: "succeeded", last_merge_source_commit: "abc123",
      description: "body", reviewers: [], work_items: []
    }.freeze

    def initialize(integration = nil, pull_request: DEFAULT_PR, error: nil, completed: true)
      @integration = integration
      @pull_request = pull_request
      @error = error
      @completed = completed
      @calls = []
    end

    def list(repository, state: "active", limit: 50, skip: 0)
      authorize!(:"repositories.read")
      record(:list, repository: repository, state: state, limit: limit, skip: skip)
      raise @error if @error

      { pull_requests: [ @pull_request ], has_more: false }
    end

    def get(repository, pull_request_id)
      authorize!(:"repositories.read")
      record(:get, repository: repository, pull_request_id: pull_request_id)
      raise @error if @error

      @pull_request
    end

    def changes(repository, pull_request_id, iteration: nil, limit: 50, skip: 0)
      authorize!(:"repositories.read")
      record(:changes, repository: repository, pull_request_id: pull_request_id, iteration: iteration)
      raise @error if @error

      { iteration: iteration || 2, changes: [ { path: "/app/x.rb", change_type: "edit" } ],
        diff_available: false, note: "File metadata only — Azure does not return a textual patch here." }
    end

    def create(repository, source_branch:, target_branch:, title:, description: nil, draft: true)
      authorize!(:"pull_requests.write")
      record(:create, repository: repository, source_branch: source_branch, target_branch: target_branch,
                      title: title, description: description, draft: draft)
      raise @error if @error

      @pull_request.merge(source_branch: source_branch, target_branch: target_branch,
                          title: title, is_draft: draft)
    end

    def update(repository, pull_request_id, attributes)
      authorize!(:"pull_requests.write")
      record(:update, repository: repository, pull_request_id: pull_request_id, attributes: attributes)
      raise @error if @error

      @pull_request.merge(attributes)
    end

    def list_threads(repository, pull_request_id, limit: 50)
      authorize!(:"repositories.read")
      record(:list_threads, repository: repository, pull_request_id: pull_request_id)
      raise @error if @error

      { threads: [ { id: 1, status: "active", comments: [ { id: 1, author: "Ada", content: "why?" } ] } ],
        has_more: false }
    end

    def create_thread(repository, pull_request_id, content:, file_path: nil, right_line: nil, iteration: nil)
      authorize!(:"pull_request_threads.write")
      record(:create_thread, repository: repository, pull_request_id: pull_request_id, content: content,
                             file_path: file_path, right_line: right_line, iteration: iteration)
      raise @error if @error

      { id: 2, status: "active", file_path: file_path, right_line: right_line,
        comments: [ { id: 5, content: content } ] }
    end

    def reply_to_thread(repository, pull_request_id, thread_id, content:)
      authorize!(:"pull_request_threads.write")
      record(:reply_to_thread, repository: repository, pull_request_id: pull_request_id,
                               thread_id: thread_id, content: content)
      raise @error if @error

      { id: 6, parent_id: 1, content: content }
    end

    def update_thread_status(repository, pull_request_id, thread_id, status:)
      authorize!(:"pull_request_threads.write")
      record(:update_thread_status, repository: repository, pull_request_id: pull_request_id,
                                    thread_id: thread_id, status: status)
      raise @error if @error

      { id: thread_id, status: status }
    end

    def reviewers(repository, pull_request_id)
      authorize!(:"repositories.read")
      record(:reviewers, repository: repository, pull_request_id: pull_request_id)
      raise @error if @error

      [ { id: "rev-1", name: "Ada", vote: 0, vote_label: "reset", required: true } ]
    end

    def add_reviewer(repository, pull_request_id, reviewer_id:, required: false)
      authorize!(:"pull_requests.write")
      record(:add_reviewer, repository: repository, pull_request_id: pull_request_id,
                            reviewer_id: reviewer_id, required: required)
      raise @error if @error

      { id: reviewer_id, vote: 0, vote_label: "reset", required: required }
    end

    def vote(repository, pull_request_id, reviewer_id:, vote:)
      value = AzureDevops::PullRequestService::VOTES[vote.to_s]
      raise AzureDevops::ValidationFailed, "vote must be one of …" if value.nil?

      authorize!(:"pull_requests.write")
      record(:vote, repository: repository, pull_request_id: pull_request_id,
                    reviewer_id: reviewer_id, vote: vote)
      raise @error if @error

      { id: reviewer_id, vote: value, vote_label: vote.to_s }
    end

    # The real adapter refuses an unknown strategy and a blank commit before it
    # sends anything, and reports acceptance rather than a merge until a re-read
    # confirms. Both behaviours are reproduced, because callers branch on them.
    def complete(repository, pull_request_id, expected_commit:, merge_strategy: "squash",
                 delete_source_branch: false, commit_message: nil)
      unless AzureDevops::PullRequestService::MERGE_STRATEGIES.include?(merge_strategy.to_s)
        raise AzureDevops::ValidationFailed, "merge_strategy must be one of …"
      end
      if expected_commit.blank?
        raise AzureDevops::ValidationFailed, "expected_commit is required to complete a pull request"
      end

      authorize!(:"pull_requests.complete")
      record(:complete, repository: repository, pull_request_id: pull_request_id,
                        expected_commit: expected_commit, merge_strategy: merge_strategy,
                        delete_source_branch: delete_source_branch, commit_message: commit_message)
      raise @error if @error

      if @completed
        @pull_request.merge(status: "completed", completed: true)
      else
        @pull_request.merge(completed: false, pending: true,
                            note: "Azure accepted the completion but the pull request has not finished merging.")
      end
    end

    def artifact_id(repository, pull_request_id)
      "vstfs:///Git/PullRequestId/#{repository.external_project_id}%2F#{repository.external_id}%2F#{pull_request_id}"
    end
  end

  # Mirrors AzureDevops::WorkItemService.
  class WorkItemService
    include Recorder

    DEFAULT_ITEM = {
      id: 11, rev: 3, type: "Bug", title: "It breaks", state: "Active",
      assigned_to: "Ada", area_path: "Customer Platform"
    }.freeze

    def initialize(integration = nil, work_item: DEFAULT_ITEM, error: nil)
      @integration = integration
      @work_item = work_item
      @error = error
      @calls = []
    end

    def work_item_types
      authorize!(:"work_items.read")
      record(:work_item_types)
      raise @error if @error

      [ { name: "Bug", reference_name: "Microsoft.VSTS.WorkItemTypes.Bug",
          states: [ { name: "Active", category: "InProgress" }, { name: "Resolved", category: "Resolved" } ],
          required_fields: [ "System.Title" ] } ]
    end

    def query(filters: {}, limit: 50, cursor: nil)
      authorize!(:"work_items.read")
      record(:query, filters: filters, limit: limit, cursor: cursor)
      raise @error if @error

      { work_items: [ @work_item ], total_matched: 1, has_more: false }
    end

    def get(work_item_id)
      authorize!(:"work_items.read")
      record(:get, work_item_id: work_item_id)
      raise @error if @error

      @work_item
    end

    def comments(work_item_id, limit: 50, cursor: nil)
      authorize!(:"work_items.read")
      record(:comments, work_item_id: work_item_id, limit: limit, cursor: cursor)
      raise @error if @error

      { comments: [ { id: 1, author: "Ada", text: "looking" } ], has_more: false }
    end

    def add_comment(work_item_id, text:)
      authorize!(:"work_items.write")
      record(:add_comment, work_item_id: work_item_id, text: text)
      raise @error if @error

      { id: 2, created_at: Time.current.iso8601 }
    end

    def create(type:, fields: {})
      raise AzureDevops::ValidationFailed, "At least System.Title is required" if fields.blank?

      authorize!(:"work_items.write")
      record(:create, type: type, fields: fields)
      raise @error if @error

      @work_item.merge(type: type, title: fields[:title])
    end

    def update(work_item_id, fields: {}, expected_revision: nil)
      authorize!(:"work_items.write")
      record(:update, work_item_id: work_item_id, fields: fields, expected_revision: expected_revision)
      raise @error if @error

      @work_item.merge(fields).merge(rev: @work_item[:rev] + 1)
    end

    def link_pull_request(work_item_id, artifact_id:, expected_revision: nil, comment: nil)
      authorize!(:"work_items.write")
      record(:link_pull_request, work_item_id: work_item_id, artifact_id: artifact_id,
                                 expected_revision: expected_revision, comment: comment)
      raise @error if @error

      @work_item.merge(relations: [ { rel: "ArtifactLink", url: artifact_id } ])
    end
  end

  # Mirrors AzureDevops::BuildService.
  class BuildService
    include Recorder

    DEFAULT_BUILD = {
      id: 4242, build_number: "20260912.1", repository_id: RepositoryService::DEFAULT_REPO[:external_id],
      status: "completed", result: "succeeded", definition: "CI",
      branch: "main", commit: "abc123"
    }.freeze

    def initialize(integration = nil, build: DEFAULT_BUILD, policies: nil, error: nil)
      @integration = integration
      @build = build
      @policies = policies
      @error = error
      @calls = []
    end

    def list(repository: nil, branch: nil, limit: 25)
      authorize!(:"builds.read")
      record(:list, repository: repository, branch: branch, limit: limit)
      raise @error if @error

      [ @build ]
    end

    def get(build_id)
      authorize!(:"builds.read")
      record(:get, build_id: build_id)
      raise @error if @error

      @build.merge(id: build_id.to_i)
    end

    def policy_evaluations(repository, pull_request_id)
      authorize!(:"builds.read")
      record(:policy_evaluations, repository: repository, pull_request_id: pull_request_id)
      raise @error if @error

      @policies || {
        repository_id: repository&.id, pull_request_id: pull_request_id.to_i,
        evaluations: [ { id: "e1", status: "approved", type: "Build", blocking: true, enabled: true } ],
        all_blocking_satisfied: true, blocking_count: 1, unsatisfied: []
      }
    end
  end
end
