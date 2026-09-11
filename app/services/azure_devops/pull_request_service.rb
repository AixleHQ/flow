# frozen_string_literal: true

module AzureDevops
  # Pull requests, their changed files, and their review threads.
  #
  # Azure's review model is threads-of-comments, not a flat comment list: a
  # reply needs the thread id, and an inline thread carries file and iteration
  # coordinates. Flattening that into "comments" is what makes an agent answer
  # the wrong conversation, so the shape is preserved rather than simplified.
  class PullRequestService
    DEFAULT_LIMIT = 50
    MAX_LIMIT = 100

    def initialize(integration)
      @integration = integration
    end

    attr_reader :integration

    def list(repository, state: "active", limit: DEFAULT_LIMIT, skip: 0)
      client, resolved = client_for(:"repositories.read")
      payload = client.get(*repo_path(repository), "pullrequests",
                           family: :git, project: resolved.project_id,
                           params: {
                             "searchCriteria.status" => azure_status(state),
                             "$top" => clamp(limit), "$skip" => skip.to_i
                           })

      items = Array(payload["value"]).map { |pr| summarize(pr) }
      { pull_requests: items, has_more: items.size >= clamp(limit),
        next_cursor: items.size >= clamp(limit) ? (skip.to_i + items.size).to_s : nil }.compact
    end

    # The list endpoint truncates `description`. Anything that needs the body —
    # which is most of what an agent reads a PR for — has to come from here.
    def get(repository, pull_request_id)
      client, resolved = client_for(:"repositories.read")
      pr = client.get(*repo_path(repository), "pullrequests", pull_request_id.to_s,
                      family: :git, project: resolved.project_id,
                      params: { includeCommits: false, includeWorkItemRefs: true })

      verify_pr_scope!(pr, repository, resolved)
      summarize(pr, full: true)
    end

    # Changed files for one iteration. Explicitly metadata: Azure returns paths
    # and change types, not a textual patch, and fabricating a diff from that
    # list is how an agent ends up reviewing code that does not exist.
    def changes(repository, pull_request_id, iteration: nil, limit: DEFAULT_LIMIT, skip: 0)
      client, resolved = client_for(:"repositories.read")
      iteration_id = iteration.presence || latest_iteration(client, resolved, repository, pull_request_id)
      payload = client.get(*repo_path(repository), "pullrequests", pull_request_id.to_s,
                           "iterations", iteration_id.to_s, "changes",
                           family: :git, project: resolved.project_id,
                           params: { "$top" => clamp(limit), "$skip" => skip.to_i, "$compareTo" => 0 })

      entries = Array(payload["changeEntries"]).map do |entry|
        { path: entry.dig("item", "path"), change_type: entry["changeType"],
          is_folder: entry.dig("item", "isFolder"), object_id: entry.dig("item", "objectId") }.compact
      end

      {
        iteration: iteration_id,
        changes: entries,
        diff_available: false,
        note: "File metadata only — Azure does not return a textual patch here. " \
              "Fetch file contents or compute a git diff over the iteration's commits for the actual changes.",
        has_more: entries.size >= clamp(limit),
        next_cursor: entries.size >= clamp(limit) ? (skip.to_i + entries.size).to_s : nil
      }.compact
    end

    # Creation is not idempotent upstream, so the operations ledger owns the
    # retry contract. Draft by default: an agent opening a PR that is
    # immediately review-ready and policy-triggering should be a deliberate act.
    def create(repository, source_branch:, target_branch:, title:, description: nil, draft: true)
      client, resolved = client_for(:"pull_requests.write")
      body = {
        # Azure requires fully qualified refs. A bare branch name is accepted by
        # nothing and produces an unhelpful validation error.
        sourceRefName: qualified_ref(source_branch),
        targetRefName: qualified_ref(target_branch),
        title: title.to_s,
        description: description.to_s,
        isDraft: draft != false
      }

      pr = client.post(*repo_path(repository), "pullrequests", body: body,
                                                               family: :git, project: resolved.project_id)
      summarize(pr, full: true)
    end

    def update(repository, pull_request_id, attributes)
      client, resolved = client_for(:"pull_requests.write")
      body = {
        title: attributes[:title],
        description: attributes[:description],
        isDraft: attributes[:draft]
      }.compact
      raise ValidationFailed, "Nothing to update" if body.empty?

      pr = client.patch(*repo_path(repository), "pullrequests", pull_request_id.to_s,
                        body: body, family: :git, project: resolved.project_id)
      summarize(pr, full: true)
    end

    def list_threads(repository, pull_request_id, limit: DEFAULT_LIMIT)
      client, resolved = client_for(:"repositories.read")
      payload = client.get(*repo_path(repository), "pullrequests", pull_request_id.to_s, "threads",
                           family: :git, project: resolved.project_id)

      threads = Array(payload["value"]).reject { |t| t["isDeleted"] }.map { |t| summarize_thread(t) }
      { threads: threads.first(clamp(limit)), has_more: threads.size > clamp(limit) }
    end

    # A general thread has no file context; an inline one carries a path plus
    # line coordinates validated against an iteration. Passing line numbers for
    # the wrong iteration silently anchors the comment to unrelated code.
    def create_thread(repository, pull_request_id, content:, file_path: nil, right_line: nil, iteration: nil)
      client, resolved = client_for(:"pull_request_threads.write")
      body = { comments: [ { parentCommentId: 0, content: content.to_s, commentType: "text" } ], status: "active" }

      if file_path.present?
        iteration_id = iteration.presence || latest_iteration(client, resolved, repository, pull_request_id)
        body[:threadContext] = {
          filePath: file_path.to_s,
          rightFileStart: { line: right_line.to_i, offset: 1 },
          rightFileEnd: { line: right_line.to_i, offset: 1 }
        }
        body[:pullRequestThreadContext] = {
          changeTrackingId: 0,
          iterationContext: { firstComparingIteration: iteration_id.to_i, secondComparingIteration: iteration_id.to_i }
        }
      end

      thread = client.post(*repo_path(repository), "pullrequests", pull_request_id.to_s, "threads",
                           body: body, family: :git, project: resolved.project_id)
      summarize_thread(thread)
    end

    def reply_to_thread(repository, pull_request_id, thread_id, content:)
      client, resolved = client_for(:"pull_request_threads.write")
      comment = client.post(*repo_path(repository), "pullrequests", pull_request_id.to_s,
                            "threads", thread_id.to_s, "comments",
                            body: { content: content.to_s, commentType: "text" },
                            family: :git, project: resolved.project_id)
      summarize_comment(comment)
    end

    def update_thread_status(repository, pull_request_id, thread_id, status:)
      allowed = %w[active fixed wontFix closed pending byDesign]
      raise ValidationFailed, "status must be one of #{allowed.join(', ')}" unless allowed.include?(status.to_s)

      client, resolved = client_for(:"pull_request_threads.write")
      thread = client.patch(*repo_path(repository), "pullrequests", pull_request_id.to_s, "threads", thread_id.to_s,
                            body: { status: status.to_s }, family: :git, project: resolved.project_id)
      summarize_thread(thread)
    end

    # PR ↔ work item is an artifact relation on the WORK ITEM, added through the
    # work item patch API — it is not a field on the pull request. Linking never
    # transitions the work item's state.
    def artifact_id(repository, pull_request_id)
      project_id = repository.external_project_id
      "vstfs:///Git/PullRequestId/#{project_id}%2F#{repository.external_id}%2F#{pull_request_id}"
    end

    private

    def client_for(capability)
      CredentialProvider.client_for(integration, capability: capability)
    end

    def repo_path(repository)
      [ "_apis", "git", "repositories", repository.external_id.to_s ]
    end

    def clamp(limit)
      (limit.presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
    end

    def azure_status(state)
      case state.to_s
      when "completed" then "completed"
      when "abandoned" then "abandoned"
      when "all" then "all"
      else "active"
      end
    end

    def qualified_ref(branch)
      name = branch.to_s
      name.start_with?("refs/") ? name : "refs/heads/#{name}"
    end

    def latest_iteration(client, resolved, repository, pull_request_id)
      payload = client.get(*repo_path(repository), "pullrequests", pull_request_id.to_s, "iterations",
                           family: :git, project: resolved.project_id)
      Array(payload["value"]).map { |i| i["id"].to_i }.max || 1
    end

    # A pull request id is only unique within a repository, and a caller could
    # name one from elsewhere. Confirm the answer is about the repository and
    # project this connection actually covers.
    def verify_pr_scope!(pr, repository, resolved)
      repo_id = pr.dig("repository", "id")
      project_id = pr.dig("repository", "project", "id")
      return if repo_id == repository.external_id && (project_id.nil? || project_id == resolved.project_id)

      raise NotAuthorized, "That pull request is not in this repository"
    end

    def summarize(pr, full: false)
      base = {
        id: pr["pullRequestId"],
        title: pr["title"],
        status: pr["status"],
        is_draft: pr["isDraft"],
        source_branch: pr["sourceRefName"].to_s.delete_prefix("refs/heads/"),
        target_branch: pr["targetRefName"].to_s.delete_prefix("refs/heads/"),
        author: pr.dig("createdBy", "displayName"),
        created_at: pr["creationDate"],
        merge_status: pr["mergeStatus"],
        url: web_url(pr)
      }
      return base.compact unless full

      base.merge(
        description: pr["description"],
        last_merge_source_commit: pr.dig("lastMergeSourceCommit", "commitId"),
        reviewers: Array(pr["reviewers"]).map { |r| { name: r["displayName"], vote: r["vote"] } },
        work_items: Array(pr["workItemRefs"]).map { |w| w["id"] }
      ).compact
    end

    def summarize_thread(thread)
      context = thread["threadContext"]
      {
        id: thread["id"],
        status: thread["status"],
        file_path: context&.dig("filePath"),
        right_line: context&.dig("rightFileStart", "line"),
        left_line: context&.dig("leftFileStart", "line"),
        published_at: thread["publishedDate"],
        comments: Array(thread["comments"]).reject { |c| c["isDeleted"] }.map { |c| summarize_comment(c) }
      }.compact
    end

    def summarize_comment(comment)
      {
        id: comment["id"],
        parent_id: comment["parentCommentId"],
        author: comment.dig("author", "displayName"),
        content: comment["content"],
        comment_type: comment["commentType"],
        published_at: comment["publishedDate"]
      }.compact
    end

    # Azure's `_links.web.href` is a provider string; it is only surfaced when it
    # is an https URL on the configured API host, so a tool result can never hand
    # an agent a link somewhere else.
    def web_url(pr)
      href = pr.dig("_links", "web", "href").to_s
      return nil if href.blank?

      uri = begin
        URI.parse(href)
      rescue URI::InvalidURIError
        nil
      end
      return nil unless uri.is_a?(URI::HTTPS)
      return nil unless uri.host == URI.parse(AppConfig.api_host).host

      href
    end
  end
end
