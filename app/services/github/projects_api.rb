# frozen_string_literal: true

module Github
  # The GitHub endpoints the Projects tracker uses, over the connection's
  # installation token, answering with plain hashes and failing with
  # Trackers::Error.
  #
  # The board (projects, fields, items, status changes) is GraphQL only. Issue
  # writes go through REST, which takes logins and label names as they are,
  # where GraphQL wants a node id for each.
  class ProjectsApi
    API_HOST = "https://api.github.com"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    MAX_PROJECT_PAGES = 5
    PERMISSION_HINT = "The Aixle GitHub App needs the Projects (organization) and Issues (repository) " \
                      "permissions, approved by an organization owner"

    CONTENT = <<~GRAPHQL
      fragment IssueParts on Issue {
        id number title body url state stateReason updatedAt
        repository { nameWithOwner }
        issueType { name }
        assignees(first: 20) { nodes { login } }
        labels(first: 50) { nodes { name } }
      }
      fragment PullParts on PullRequest {
        id number title body url state updatedAt
        repository { nameWithOwner }
        assignees(first: 20) { nodes { login } }
        labels(first: 50) { nodes { name } }
      }
      fragment Placement on ProjectV2Item {
        id
        project { id }
        fieldValueByName(name: $field) { ... on ProjectV2ItemFieldSingleSelectValue { name optionId } }
      }
    GRAPHQL

    WITH_PLACEMENTS = <<~GRAPHQL
      ... on Issue { ...IssueParts projectItems(first: 20, includeArchived: false) { nodes { ...Placement } } }
      ... on PullRequest { ...PullParts projectItems(first: 20, includeArchived: false) { nodes { ...Placement } } }
    GRAPHQL

    def self.for(integration) = new(integration)

    def initialize(integration)
      @integration = integration
    end

    # The organization's projects: [{ id:, number:, title:, url:, closed: }].
    def projects(login)
      all = []
      cursor = nil
      MAX_PROJECT_PAGES.times do
        data = graphql(<<~GRAPHQL, login: login, after: cursor)
          query($login: String!, $after: String) {
            organization(login: $login) {
              projectsV2(first: 100, after: $after, orderBy: { field: TITLE, direction: ASC }) {
                pageInfo { hasNextPage endCursor }
                nodes { id number title url closed }
              }
            }
          }
        GRAPHQL
        page = data.dig("organization", "projectsV2")
        raise Trackers::Error.new("GitHub has no organization #{login}", code: "not_found") unless page

        all.concat(page["nodes"].compact.map { |p| p.slice("id", "number", "title", "url", "closed").symbolize_keys })
        break unless page.dig("pageInfo", "hasNextPage")

        cursor = page.dig("pageInfo", "endCursor")
      end
      all
    end

    # A project and its single-select field `field`: { id:, number:, title:, url:,
    # owner:, field: { id:, name:, options: [{ id:, name: }] } | nil }.
    def project(project_id, field:)
      data = graphql(<<~GRAPHQL, id: project_id, field: field)
        query($id: ID!, $field: String!) {
          node(id: $id) {
            ... on ProjectV2 {
              id number title url
              owner { ... on Organization { login } }
              field(name: $field) { ... on ProjectV2SingleSelectField { id name options { id name } } }
            }
          }
        }
      GRAPHQL
      node = data["node"]
      raise Trackers::Error.new("GitHub has no such project, or this connection cannot see it", code: "not_found") if node.blank?

      field_data = node["field"].presence
      {
        id: node["id"], number: node["number"], title: node["title"], url: node["url"], owner: node.dig("owner", "login"),
        field: field_data && { id: field_data["id"], name: field_data["name"],
                               options: field_data["options"].map { |o| { id: o["id"], name: o["name"] } } }
      }
    end

    # The organization's issue types, when it defines any: [{ id:, name: }].
    def issue_types(login)
      data = graphql(<<~GRAPHQL, login: login)
        query($login: String!) { organization(login: $login) { issueTypes(first: 25) { nodes { id name isEnabled } } } }
      GRAPHQL
      Array(data.dig("organization", "issueTypes", "nodes")).select { |t| t["isEnabled"] != false }
                                                           .map { |t| { id: t["id"], name: t["name"] } }
    end

    # An issue or pull request by node id, with the project items it sits in.
    def content(node_id, field:)
      data = graphql(<<~GRAPHQL, id: node_id, field: field)
        query($id: ID!, $field: String!) { node(id: $id) { #{WITH_PLACEMENTS} } }
        #{CONTENT}
      GRAPHQL
      normalize_content(data["node"])
    end

    def content_by_number(owner:, repo:, number:, field:)
      data = graphql(<<~GRAPHQL, owner: owner, repo: repo, number: number.to_i, field: field)
        query($owner: String!, $repo: String!, $number: Int!, $field: String!) {
          repository(owner: $owner, name: $repo) { issueOrPullRequest(number: $number) { #{WITH_PLACEMENTS} } }
        }
        #{CONTENT}
      GRAPHQL
      normalize_content(data.dig("repository", "issueOrPullRequest"))
    end

    # One page of a project's items, filtered with GitHub's project filter
    # syntax: { items: [content with `item`], next_cursor: }. Draft issues are
    # left out; they are not issues anywhere else.
    def items(project_id, query:, field:, limit:, cursor: nil)
      data = graphql(<<~GRAPHQL, id: project_id, query: query.to_s, field: field, first: limit, after: cursor.presence)
        query($id: ID!, $query: String!, $field: String!, $first: Int!, $after: String) {
          node(id: $id) {
            ... on ProjectV2 {
              items(first: $first, after: $after, query: $query) {
                pageInfo { hasNextPage endCursor }
                nodes {
                  ...Placement
                  content { ... on Issue { ...IssueParts } ... on PullRequest { ...PullParts } }
                }
              }
            }
          }
        }
        #{CONTENT}
      GRAPHQL
      page = data.dig("node", "items")
      raise Trackers::Error.new("GitHub has no such project", code: "not_found") unless page

      items = page["nodes"].compact.filter_map do |node|
        content = normalize_content(node["content"], placements: [ node ])
        content if content
      end
      { items: items, next_cursor: page.dig("pageInfo", "hasNextPage") ? page.dig("pageInfo", "endCursor") : nil }
    end

    def comments(node_id, limit:, cursor: nil)
      data = graphql(<<~GRAPHQL, id: node_id, first: limit, after: cursor.presence)
        query($id: ID!, $first: Int!, $after: String) {
          node(id: $id) {
            ... on Issue { comments(first: $first, after: $after) { ...Comments } }
            ... on PullRequest { comments(first: $first, after: $after) { ...Comments } }
          }
        }
        fragment Comments on IssueCommentConnection {
          pageInfo { hasNextPage endCursor }
          nodes { id body createdAt author { login } }
        }
      GRAPHQL
      page = data.dig("node", "comments") || { "nodes" => [] }
      { comments: page["nodes"].compact.map { |c| comment(c) },
        next_cursor: page.dig("pageInfo", "hasNextPage") ? page.dig("pageInfo", "endCursor") : nil }
    end

    def add_comment(node_id, body)
      data = graphql(<<~GRAPHQL, id: node_id, body: body.to_s, write: true)
        mutation($id: ID!, $body: String!) {
          addComment(input: { subjectId: $id, body: $body }) { commentEdge { node { id body createdAt author { login } } } }
        }
      GRAPHQL
      comment(data.dig("addComment", "commentEdge", "node").to_h)
    end

    def set_status(project_id:, item_id:, field_id:, option_id:)
      graphql(<<~GRAPHQL, project: project_id, item: item_id, field: field_id, option: option_id, write: true)
        mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
          updateProjectV2ItemFieldValue(input: {
            projectId: $project, itemId: $item, fieldId: $field, value: { singleSelectOptionId: $option }
          }) { projectV2Item { id } }
        }
      GRAPHQL
      true
    end

    # The item's node id.
    def add_to_project(project_id, content_id)
      data = graphql(<<~GRAPHQL, project: project_id, content: content_id, write: true)
        mutation($project: ID!, $content: ID!) {
          addProjectV2ItemById(input: { projectId: $project, contentId: $content }) { item { id } }
        }
      GRAPHQL
      data.dig("addProjectV2ItemById", "item", "id")
    end

    # { node_id:, key: } of the new issue. `type` is an organization issue type name.
    def create_issue(repository, title:, body: nil, assignees: [], labels: [], type: nil)
      raw = rest(:post, "/repos/#{repository_path(repository)}/issues",
                 { title: title, body: body, assignees: assignees.presence, labels: labels.presence, type: type }.compact)
      { node_id: raw["node_id"], key: "#{repository}##{raw['number']}" }
    end

    # `attributes`: title, body, state, assignees (the full list).
    def update_issue(repository, number, attributes)
      rest(:patch, "/repos/#{repository_path(repository)}/issues/#{number.to_i}", attributes)
    end

    def set_labels(repository, number, labels)
      rest(:put, "/repos/#{repository_path(repository)}/issues/#{number.to_i}/labels", { labels: labels })
    end

    def add_labels(repository, number, labels)
      rest(:post, "/repos/#{repository_path(repository)}/issues/#{number.to_i}/labels", { labels: labels })
    end

    def remove_label(repository, number, label)
      rest(:delete, "/repos/#{repository_path(repository)}/issues/#{number.to_i}/labels/#{ERB::Util.url_encode(label)}")
    rescue Trackers::Error => e
      raise unless e.code == "not_found"
    end

    private

    def graphql(query, write: false, **variables)
      body = post_json("/graphql", { query: query, variables: variables.compact }, write: write)
      errors = Array(body["errors"])
      raise graphql_error(errors.first) if errors.any?

      body["data"].to_h
    end

    def rest(method, path, body = nil)
      request(method, path, body, write: method != :get)
    end

    def post_json(path, body, write:)
      request(:post, path, body, write: write)
    end

    def request(method, path, body, write:)
      response = connection.run_request(method, path, body&.to_json, headers)
      log(method, path, response)
      return parse(response) if response.success?

      raise http_error(response, write: write)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Trackers::Error::OutcomeUnknown, "GitHub did not answer (#{e.class})" if write

      raise Trackers::Error.new("GitHub did not answer (#{e.class})", code: "timeout")
    end

    def headers
      {
        "Accept" => "application/vnd.github+json", "Content-Type" => "application/json",
        "X-GitHub-Api-Version" => "2022-11-28", "Authorization" => "Bearer #{token}"
      }
    end

    def token
      @token ||= Github::TokenService.new(@integration).generate_installation_token
    rescue Github::TokenService::ConfigurationError, Github::TokenService::AuthenticationError => e
      raise Trackers::Error.new("GitHub refused this connection: #{e.message}", code: "not_authorized")
    end

    def parse(response)
      response.body.present? ? JSON.parse(response.body) : {}
    rescue JSON::ParserError
      raise Trackers::Error.new("GitHub returned a non-JSON body", code: "provider_error")
    end

    # GraphQL answers 200 with an error list; `type` is the stable part.
    def graphql_error(error)
      message = error["message"].to_s.truncate(300)
      code = case error["type"]
      when "NOT_FOUND" then "not_found"
      when "FORBIDDEN", "INSUFFICIENT_SCOPES" then "permission_denied"
      when "RATE_LIMITED" then "rate_limited"
      else "validation_failed"
      end
      message = "#{message}. #{PERMISSION_HINT}" if code == "permission_denied"
      Trackers::Error.new(message, code: code)
    end

    def http_error(response, write:)
      message = error_message(response)
      case response.status
      when 401 then Trackers::Error.new("GitHub rejected this connection's token", code: "not_authorized")
      when 403, 429
        if response.status == 429 || response.headers["x-ratelimit-remaining"] == "0" || response.headers["retry-after"]
          Trackers::Error.new("GitHub is rate limiting this connection", code: "rate_limited",
                                                                       details: { retry_after: response.headers["retry-after"] })
        else
          Trackers::Error.new("#{message}. #{PERMISSION_HINT}", code: "permission_denied")
        end
      when 404 then Trackers::Error.new(message.presence || "GitHub has no such resource", code: "not_found")
      when 410, 422 then Trackers::Error.new(message, code: "validation_failed")
      when 500..599
        write ? Trackers::Error::OutcomeUnknown.new("GitHub returned #{response.status} on a write") :
                Trackers::Error.new("GitHub returned #{response.status}", code: "provider_error")
      else Trackers::Error.new(message, code: "provider_error")
      end
    end

    def error_message(response)
      body = JSON.parse(response.body.to_s)
      details = Array(body["errors"]).filter_map { |e| e.is_a?(Hash) ? (e["message"] || [ e["field"], e["code"] ].compact.join(" ")) : e }
      [ body["message"], *details ].compact_blank.join(": ").truncate(300).presence || "GitHub returned #{response.status}"
    rescue JSON::ParserError
      "GitHub returned #{response.status}"
    end

    def normalize_content(node, placements: nil)
      return if node.blank? || node["id"].blank? || node["repository"].blank?

      repository = node.dig("repository", "nameWithOwner")
      pull = node["id"].to_s.start_with?("PR_")
      {
        id: node["id"], number: node["number"], key: "#{repository}##{node['number']}", url: node["url"],
        title: node["title"], body: node["body"], state: node["state"], state_reason: node["stateReason"],
        type: node.dig("issueType", "name") || (pull ? "Pull request" : "Issue"), pull_request: pull,
        repository: repository, updated_at: node["updatedAt"],
        assignees: Array(node.dig("assignees", "nodes")).filter_map { |a| a["login"] },
        labels: Array(node.dig("labels", "nodes")).filter_map { |l| l["name"] },
        placements: Array(placements || node.dig("projectItems", "nodes")).compact.map do |item|
          { item_id: item["id"], project_id: item.dig("project", "id"), status: item.dig("fieldValueByName", "name"),
            option_id: item.dig("fieldValueByName", "optionId") }
        end
      }
    end

    def comment(raw)
      { id: raw["id"], body: raw["body"], created_at: raw["createdAt"], author: raw.dig("author", "login") }
    end

    def repository_path(repository)
      owner, name = repository.to_s.split("/", 2)
      raise Trackers::Error.new("'#{repository}' is not owner/repo", code: "validation_failed") if owner.blank? || name.blank?

      "#{ERB::Util.url_encode(owner)}/#{ERB::Util.url_encode(name)}"
    end

    def connection
      @connection ||= Faraday.new(url: API_HOST) do |f|
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = READ_TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end

    def log(method, path, response)
      Rails.logger.info("[Github::ProjectsApi] #{method.to_s.upcase} #{path} status=#{response.status} " \
                        "request_id=#{response.headers['x-github-request-id']}")
    end
  end
end
