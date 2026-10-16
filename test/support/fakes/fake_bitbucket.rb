# frozen_string_literal: true

# In-memory fake of Bitbucket::Api (docs/testing.md R3). Callers — the
# integration, repository and check-status services, the pull-request provider,
# controllers — get it from `stub_bitbucket!`. Every hash it answers has the
# shape test/services/bitbucket/api_test.rb pins the real adapter to (R4).
#
# One workspace, acme, holding one repository, acme/api, with an open pull
# request #7 from feature → main.
module FakeBitbucket
  class Api
    WORKSPACE_UUID = "{8f1d6b2a-0000-4000-8000-00000000b17b}"
    PROJECT_UUID = "{3c2b1a00-0000-4000-8000-0000000000aa}"
    REPOSITORY_UUID = "{5e4d3c2b-0000-4000-8000-0000000000a1}"
    HEAD = "e3c6ad85c1b5"

    attr_reader :calls, :pull_request_store, :comment_store, :statuses, :repository_list, :branches_by_repository
    attr_accessor :user, :workspaces, :merge_mode

    def initialize
      @calls = []
      @failures = {}
      @user = nil
      @workspaces = { "acme" => { uuid: WORKSPACE_UUID, slug: "acme", name: "Acme" } }
      @repository_list = []
      @branches_by_repository = Hash.new { |h, k| h[k] = [] }
      @pull_request_store = Hash.new { |h, k| h[k] = {} }
      @comment_store = Hash.new { |h, k| h[k] = [] }
      @statuses = Hash.new { |h, k| h[k] = [] }
      @merge_mode = :merged
      @next_id = 100
      add_repository(full_name: "acme/api", uuid: REPOSITORY_UUID, branches: %w[main feature])
      add_pull_request(REPOSITORY_UUID, id: 7, title: "Add billing", source_branch: "feature", target_branch: "main")
    end

    def add_repository(full_name:, uuid: "{#{SecureRandom.uuid}}", workspace_uuid: WORKSPACE_UUID, is_private: true,
                       default_branch: "main", branches: [ default_branch ])
      workspace_slug, slug = full_name.split("/", 2)
      repository = { uuid: uuid, full_name: full_name, slug: slug, name: slug, workspace_uuid: workspace_uuid,
                     workspace_slug: workspace_slug, project_uuid: PROJECT_UUID, project_key: "PRJ",
                     default_branch: default_branch, is_private: is_private, description: "The #{slug} service" }
      @repository_list << repository
      @branches_by_repository[uuid] = branches
      repository
    end

    def add_pull_request(repository_uuid, id:, title:, source_branch:, target_branch: "main", state: "OPEN", head: HEAD,
                         draft: false)
      @pull_request_store[repository_uuid][id] = {
        id: id, title: title, description: "", state: state, draft: draft, source_branch: source_branch,
        source_commit: head, source_repository_uuid: repository_uuid, destination_branch: target_branch,
        destination_repository_uuid: repository_uuid, merge_commit: nil, author: "Aixle Flow", reviewers: [],
        participants: [], created_on: "2026-10-16T09:00:00.000000+00:00", updated_on: "2026-10-16T09:00:00.000000+00:00"
      }
    end

    def add_status(commit, state:, name: "Pipeline", key: SecureRandom.hex(4))
      @statuses[commit] << { key: key, name: name, state: state, url: "https://bitbucket.org/acme/api/pipelines/1",
                             refname: nil }
    end

    # The next call to `method` raises `error` (a real Bitbucket::Error subclass).
    def fail_on(method, error)
      @failures[method] = error
    end

    def called?(method) = @calls.any? { |call| call[:method] == method }
    def calls_to(method) = @calls.select { |call| call[:method] == method }

    def current_user
      record(:current_user)
      raise Bitbucket::Error::NotAuthorized, "Token is invalid or not supported for this endpoint" unless @user

      @user
    end

    def workspace(workspace)
      record(:workspace, workspace: workspace)
      find_workspace(workspace) || raise(Bitbucket::Error::NotFound)
    end

    def first_repository(workspace)
      record(:first_repository, workspace: workspace)
      in_workspace(workspace).first
    end

    def repositories(workspace, limit: 1000)
      record(:repositories, workspace: workspace)
      in_workspace(workspace).first(limit)
    end

    def repository(workspace, repository)
      record(:repository, workspace: workspace, repository: repository)
      find_repository(workspace, repository) || raise(Bitbucket::Error::NotFound)
    end

    def branches(workspace, repository, limit: 1000)
      record(:branches, workspace: workspace, repository: repository)
      repo = find_repository(workspace, repository) || raise(Bitbucket::Error::NotFound)
      @branches_by_repository[repo[:uuid]].first(limit)
    end

    def pull_requests(workspace, repository, state: "open", source_branch: nil, target_branch: nil, cursor: nil, limit: 50)
      record(:pull_requests, workspace: workspace, repository: repository, state: state, source_branch: source_branch)
      states = Bitbucket::Api::STATES.fetch(state.presence || "open")
      items = prs_of(workspace, repository).values.select do |pr|
        states.include?(pr[:state]) && (source_branch.nil? || pr[:source_branch] == source_branch) &&
          (target_branch.nil? || pr[:destination_branch] == target_branch)
      end
      [ items.first(limit), nil ]
    end

    def pull_request(workspace, repository, id)
      record(:pull_request, workspace: workspace, repository: repository, id: id)
      prs_of(workspace, repository)[id.to_i] || raise(Bitbucket::Error::NotFound)
    end

    def create_pull_request(workspace, repository, title:, source_branch:, target_branch: nil, description: nil, draft: false)
      record(:create_pull_request, workspace: workspace, repository: repository, title: title, source_branch: source_branch,
                                   target_branch: target_branch, draft: draft)
      uuid = find_repository(workspace, repository)&.dig(:uuid) || raise(Bitbucket::Error::NotFound)
      pr = add_pull_request(uuid, id: @next_id += 1, title: title, source_branch: source_branch,
                                  target_branch: target_branch || "main", draft: draft)
      pr[:description] = description.to_s
      pr
    end

    def update_pull_request(workspace, repository, id, title:, description: nil, target_branch: nil, draft: nil)
      record(:update_pull_request, workspace: workspace, repository: repository, id: id, title: title,
                                   description: description, target_branch: target_branch, draft: draft)
      pr = pull_request(workspace, repository, id)
      pr[:title] = title
      pr[:description] = description unless description.nil?
      pr[:destination_branch] = target_branch if target_branch
      pr[:draft] = draft unless draft.nil?
      pr
    end

    def decline_pull_request(workspace, repository, id)
      record(:decline_pull_request, workspace: workspace, repository: repository, id: id)
      pull_request(workspace, repository, id).tap { |pr| pr[:state] = "DECLINED" }
    end

    def merge_pull_request(workspace, repository, id, strategy: nil, close_source_branch: nil, message: nil)
      record(:merge_pull_request, workspace: workspace, repository: repository, id: id, strategy: strategy,
                                  close_source_branch: close_source_branch, message: message)
      pr = pull_request(workspace, repository, id)
      return { task_id: "task-#{id}" } if @merge_mode == :async

      pr[:state] = "MERGED"
      pr[:merge_commit] = "f00dfeed1234"
      { pull_request: pr }
    end

    def merge_task(workspace, repository, id, task_id)
      record(:merge_task, workspace: workspace, repository: repository, id: id, task_id: task_id)
      return { status: "PENDING", pull_request: nil } if @merge_mode == :async

      { status: "SUCCESS", pull_request: pull_request(workspace, repository, id) }
    end

    def comments(workspace, repository, id, cursor: nil, limit: 50)
      record(:comments, workspace: workspace, repository: repository, id: id)
      [ @comment_store[[ uuid_of(workspace, repository), id.to_i ]].first(limit), nil ]
    end

    def create_comment(workspace, repository, id, body:, path: nil, line: nil, parent_id: nil)
      record(:create_comment, workspace: workspace, repository: repository, id: id, body: body, path: path, line: line,
                              parent_id: parent_id)
      pull_request(workspace, repository, id)
      comment = { id: @next_id += 1, parent_id: parent_id&.to_i, author: "Aixle Flow", body: body, path: path,
                  line: line&.to_i, resolved: false, created_on: "2026-10-16T09:05:00.000000+00:00" }
      @comment_store[[ uuid_of(workspace, repository), id.to_i ]] << comment
      comment
    end

    def approve(workspace, repository, id)
      record(:approve, workspace: workspace, repository: repository, id: id)
      participant("approved")
    end

    def unapprove(workspace, repository, id)
      record(:unapprove, workspace: workspace, repository: repository, id: id)
      nil
    end

    def request_changes(workspace, repository, id)
      record(:request_changes, workspace: workspace, repository: repository, id: id)
      participant("changes_requested")
    end

    def diffstat(workspace, repository, id, cursor: nil, limit: 100)
      record(:diffstat, workspace: workspace, repository: repository, id: id)
      pull_request(workspace, repository, id)
      [ [ { path: "app/billing.rb", old_path: nil, status: "added", additions: 12, deletions: 0 } ], nil ]
    end

    def commit_statuses(workspace, repository, commit)
      record(:commit_statuses, workspace: workspace, repository: repository, commit: commit)
      @statuses[commit]
    end

    private

    def record(method, **args)
      @calls << { method: method, **args }
      error = @failures.delete(method)
      raise error if error
    end

    def find_workspace(ref)
      @workspaces.values.find { |w| w[:uuid] == ref.to_s || w[:slug] == ref.to_s }
    end

    def in_workspace(ref)
      workspace = find_workspace(ref)
      workspace ? @repository_list.select { |repo| repo[:workspace_uuid] == workspace[:uuid] } : []
    end

    def find_repository(workspace, ref)
      in_workspace(workspace).find { |repo| repo[:uuid] == ref.to_s || repo[:slug] == ref.to_s }
    end

    def uuid_of(workspace, repository) = find_repository(workspace, repository)&.dig(:uuid)

    def prs_of(workspace, repository)
      uuid = uuid_of(workspace, repository) || raise(Bitbucket::Error::NotFound)
      @pull_request_store[uuid]
    end

    def participant(state)
      { user: "Aixle Flow", role: "PARTICIPANT", approved: state == "approved", state: state,
        participated_on: "2026-10-16T09:10:00.000000+00:00" }
    end
  end
end
