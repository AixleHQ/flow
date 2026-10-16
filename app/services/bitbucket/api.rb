# frozen_string_literal: true

module Bitbucket
  # Typed Bitbucket Cloud REST 2.0 calls, answered as plain symbol-keyed hashes
  # so no Bitbucket JSON leaks into callers. The one seam tests replace
  # (FakeBitbucket::Api via `stub_bitbucket!`); test/services/bitbucket/api_test.rb
  # pins it to Bitbucket's payloads.
  #
  # `workspace` and `repository` are each one path segment: a slug or a braced
  # UUID. Callers that hold a Repository row pass its UUIDs, so a rename cannot
  # send a call to whatever now owns the old name.
  class Api
    REPOSITORY_PAGE = 100
    # Bitbucket refuses a larger page for pull requests and their comments.
    PULL_REQUEST_PAGE = 50
    STATES = { "open" => %w[OPEN], "merged" => %w[MERGED], "closed" => %w[DECLINED SUPERSEDED],
               "all" => %w[OPEN MERGED DECLINED SUPERSEDED] }.freeze

    def self.for(integration) = new(CredentialProvider.new(integration).credential)

    def initialize(credential, client: nil)
      @client = client || Client.new(credential: credential)
    end

    def current_user
      user = @client.get("user")
      { uuid: Identifiers.uuid(user["uuid"]), account_id: user["account_id"], display_name: user["display_name"],
        nickname: user["nickname"] }
    end

    def workspace(workspace)
      data = @client.get("workspaces", workspace)
      { uuid: Identifiers.uuid(data["uuid"]), slug: data["slug"], name: data["name"].presence || data["slug"] }
    end

    # The first repository the credential reaches in `workspace`, or nil — how a
    # token with no user of its own (an access token) is told apart and checked.
    def first_repository(workspace)
      values, = @client.page("repositories", workspace, params: { pagelen: 1 })
      values.first && repository_hash(values.first)
    end

    # Up to `count` repositories the credential reaches — enough to tell a token
    # scoped to one repository from one that reaches more.
    def repository_sample(workspace, count: 2)
      values, = @client.page("repositories", workspace, params: { pagelen: count })
      values.map { |repo| repository_hash(repo) }
    end

    def repositories(workspace, limit: 1000)
      values, = @client.paginate("repositories", workspace, params: { pagelen: REPOSITORY_PAGE, role: "member" },
                                                            limit: limit)
      values.map { |repo| repository_hash(repo) }
    end

    def repository(workspace, repository)
      repository_hash(@client.get("repositories", workspace, repository))
    end

    def branches(workspace, repository, limit: 1000)
      values, = @client.paginate("repositories", workspace, repository, "refs", "branches",
                                 params: { pagelen: REPOSITORY_PAGE }, limit: limit)
      values.filter_map { |branch| branch["name"].presence }
    end

    def pull_requests(workspace, repository, state: "open", source_branch: nil, target_branch: nil, cursor: nil,
                      limit: PULL_REQUEST_PAGE)
      states = STATES.fetch(state.presence || "open") { raise Error::ValidationFailed, "unknown state #{state.inspect}" }
      filters = []
      filters << %(source.branch.name="#{quoted(source_branch)}") if source_branch.present?
      filters << %(destination.branch.name="#{quoted(target_branch)}") if target_branch.present?
      params = { state: states, pagelen: limit.to_i.clamp(1, PULL_REQUEST_PAGE), q: filters.join(" AND ").presence }
      values, next_cursor = @client.page("repositories", workspace, repository, "pullrequests", params: params.compact,
                                                                                               cursor: cursor)
      [ values.map { |pr| pull_request_hash(pr) }, next_cursor ]
    end

    def pull_request(workspace, repository, id)
      pull_request_hash(@client.get("repositories", workspace, repository, "pullrequests", id))
    end

    def create_pull_request(workspace, repository, title:, source_branch:, target_branch: nil, description: nil, draft: false)
      body = { title: title, source: { branch: { name: source_branch } }, draft: draft == true,
               description: description.to_s, close_source_branch: false }
      body[:destination] = { branch: { name: target_branch } } if target_branch.present?
      pull_request_hash(@client.post("repositories", workspace, repository, "pullrequests", body: body))
    end

    # Bitbucket replaces what it is sent, so only the fields to change go out —
    # and the title always, which it will not accept a PUT without.
    def update_pull_request(workspace, repository, id, title:, description: nil, target_branch: nil, draft: nil)
      body = { title: title }
      body[:description] = description unless description.nil?
      body[:destination] = { branch: { name: target_branch } } if target_branch.present?
      body[:draft] = draft unless draft.nil?
      pull_request_hash(@client.put("repositories", workspace, repository, "pullrequests", id, body: body))
    end

    def decline_pull_request(workspace, repository, id)
      pull_request_hash(@client.post("repositories", workspace, repository, "pullrequests", id, "decline"))
    end

    # { pull_request: } when Bitbucket merged at once, { task_id: } when it
    # queued the merge and answered 202 with the task to poll.
    def merge_pull_request(workspace, repository, id, strategy: nil, close_source_branch: nil, message: nil)
      body = { merge_strategy: strategy, close_source_branch: close_source_branch, message: message.presence }.compact
      response = @client.post("repositories", workspace, repository, "pullrequests", id, "merge", body: body, raw: true)
      return { pull_request: pull_request_hash(response.body) } unless response.status == 202

      location = response.headers.find { |key, _| key.to_s.casecmp?("location") }&.last.to_s
      { task_id: location[%r{/task-status/([^/?#]+)}, 1] }
    end

    # { status: "PENDING" | "SUCCESS", pull_request: } — the merged pull request
    # once the task succeeded.
    def merge_task(workspace, repository, id, task_id)
      data = @client.get("repositories", workspace, repository, "pullrequests", id, "merge", "task-status", task_id)
      { status: data["task_status"].to_s, pull_request: data["merge_result"].is_a?(Hash) ? pull_request_hash(data["merge_result"]) : nil }
    end

    def comments(workspace, repository, id, cursor: nil, limit: PULL_REQUEST_PAGE)
      values, next_cursor = @client.page("repositories", workspace, repository, "pullrequests", id, "comments",
                                         params: { pagelen: limit.to_i.clamp(1, PULL_REQUEST_PAGE) }, cursor: cursor)
      [ values.reject { |comment| comment["deleted"] }.map { |comment| comment_hash(comment) }, next_cursor ]
    end

    def create_comment(workspace, repository, id, body:, path: nil, line: nil, parent_id: nil)
      payload = { content: { raw: body } }
      payload[:inline] = { path: path, to: line&.to_i }.compact if path.present?
      payload[:parent] = { id: parent_id.to_i } if parent_id.present?
      comment_hash(@client.post("repositories", workspace, repository, "pullrequests", id, "comments", body: payload))
    end

    def approve(workspace, repository, id)
      participant_hash(@client.post("repositories", workspace, repository, "pullrequests", id, "approve"))
    end

    def unapprove(workspace, repository, id)
      @client.request_delete("repositories", workspace, repository, "pullrequests", id, "approve")
      nil
    end

    def request_changes(workspace, repository, id)
      participant_hash(@client.post("repositories", workspace, repository, "pullrequests", id, "request-changes"))
    end

    def diffstat(workspace, repository, id, cursor: nil, limit: REPOSITORY_PAGE)
      values, next_cursor = @client.page("repositories", workspace, repository, "pullrequests", id, "diffstat",
                                         params: { pagelen: limit.to_i.clamp(1, REPOSITORY_PAGE) }, cursor: cursor)
      [ values.map { |change| file_change_hash(change) }, next_cursor ]
    end

    def commit_statuses(workspace, repository, commit)
      values, = @client.paginate("repositories", workspace, repository, "commit", commit, "statuses",
                                 params: { pagelen: REPOSITORY_PAGE }, limit: 500)
      values.map { |status| status_hash(status) }
    end

    private

    # Values go into a BBQL string literal; a quote or backslash in a branch name
    # must not end it.
    def quoted(value) = value.to_s.gsub(/["\\]/) { |char| "\\#{char}" }

    def repository_hash(repo)
      workspace = repo["workspace"].presence || repo["owner"] || {}
      full_name = repo["full_name"].to_s
      {
        uuid: Identifiers.uuid(repo["uuid"]),
        full_name: full_name,
        slug: full_name.split("/", 2).last,
        name: repo["name"],
        workspace_uuid: Identifiers.uuid(workspace["uuid"]),
        workspace_slug: workspace["slug"].presence || full_name.split("/", 2).first,
        project_uuid: Identifiers.uuid(repo.dig("project", "uuid")),
        project_key: repo.dig("project", "key"),
        default_branch: repo.dig("mainbranch", "name").presence,
        is_private: repo["is_private"] != false,
        description: repo["description"].presence
      }
    end

    def pull_request_hash(pr)
      {
        id: pr["id"],
        title: pr["title"],
        description: pr.dig("summary", "raw") || pr["description"],
        state: pr["state"],
        draft: pr["draft"] == true,
        source_branch: pr.dig("source", "branch", "name"),
        source_commit: pr.dig("source", "commit", "hash"),
        source_repository_uuid: Identifiers.uuid(pr.dig("source", "repository", "uuid")),
        destination_branch: pr.dig("destination", "branch", "name"),
        destination_repository_uuid: Identifiers.uuid(pr.dig("destination", "repository", "uuid")),
        merge_commit: pr.dig("merge_commit", "hash"),
        author: pr.dig("author", "display_name"),
        reviewers: Array(pr["reviewers"]).filter_map { |reviewer| reviewer["display_name"] },
        participants: Array(pr["participants"]).map { |participant| participant_hash(participant) },
        created_on: pr["created_on"],
        updated_on: pr["updated_on"]
      }
    end

    def participant_hash(participant)
      return {} unless participant.is_a?(Hash)

      { user: participant.dig("user", "display_name"), role: participant["role"], approved: participant["approved"] == true,
        state: participant["state"], participated_on: participant["participated_on"] }
    end

    def comment_hash(comment)
      {
        id: comment["id"],
        parent_id: comment.dig("parent", "id"),
        author: comment.dig("user", "display_name"),
        body: comment.dig("content", "raw"),
        path: comment.dig("inline", "path"),
        line: comment.dig("inline", "to") || comment.dig("inline", "from"),
        resolved: comment["resolution"].present?,
        created_on: comment["created_on"]
      }
    end

    def file_change_hash(change)
      {
        path: change.dig("new", "path") || change.dig("old", "path"),
        old_path: change.dig("old", "path"),
        status: change["status"],
        additions: change["lines_added"].to_i,
        deletions: change["lines_removed"].to_i
      }
    end

    def status_hash(status)
      { key: status["key"], name: status["name"].presence || status["key"], state: status["state"], url: status["url"],
        refname: status["refname"] }
    end
  end
end
