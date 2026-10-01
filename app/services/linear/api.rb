# frozen_string_literal: true

module Linear
  # The Linear GraphQL operations Aixle uses, one method each, answering with
  # plain hashes.
  class Api
    ISSUE = <<~GRAPHQL
      fragment IssueParts on Issue {
        id identifier number title description url priority updatedAt
        team { id key }
        state { id name type }
        assignee { id name displayName email }
        labels(first: 50) { nodes { id name } }
      }
    GRAPHQL
    COMMENT = "id body createdAt user { id name displayName } botActor { name }"
    PAGE_LIMIT = 100
    MAX_PAGES = 10
    WEBHOOK_RESOURCES = %w[Issue Comment].freeze

    def self.for(integration)
      new(Client.new(credential: Credential.new(integration)))
    end

    def initialize(client)
      @client = client
    end

    # Who the credential acts as, and in which workspace.
    def identity
      data = @client.query("query { viewer { id name displayName email app } organization { id name urlKey } }")
      viewer = data["viewer"].to_h
      organization = data["organization"].to_h
      {
        id: viewer["id"], name: viewer["name"], display_name: viewer["displayName"], email: viewer["email"],
        app: viewer["app"] == true,
        organization: { id: organization["id"], name: organization["name"], url_key: organization["urlKey"] }
      }
    end

    # Teams this credential can see: [{ id:, key:, name: }].
    def teams
      paged do |after|
        @client.query(<<~GRAPHQL, first: PAGE_LIMIT, after: after)["teams"]
          query($first: Int!, $after: String) {
            teams(first: $first, after: $after) { nodes { id key name } pageInfo { hasNextPage endCursor } }
          }
        GRAPHQL
      end.map { |t| { id: t["id"], key: t["key"], name: t["name"] } }
    end

    # The team's workflow states, in board order: [{ id:, name:, type: }].
    def states(team_id)
      data = @client.query(<<~GRAPHQL, team: team_id.to_s)
        query($team: String!) { team(id: $team) { states(first: 100) { nodes { id name type position } } } }
      GRAPHQL
      Array(data.dig("team", "states", "nodes")).sort_by { |s| s["position"].to_f }
                                                 .map { |s| { id: s["id"], name: s["name"], type: s["type"] } }
    end

    # Labels an issue of the team can carry: the team's and the workspace's.
    def labels(team_id)
      data = @client.query(<<~GRAPHQL, team: team_id.to_s)
        query($team: ID!) {
          issueLabels(first: 250, filter: { or: [{ team: { id: { eq: $team } } }, { team: { null: true } }] }) {
            nodes { id name isGroup }
          }
        }
      GRAPHQL
      Array(data.dig("issueLabels", "nodes")).reject { |l| l["isGroup"] }.map { |l| { id: l["id"], name: l["name"] } }
    end

    # The team's active members, matching `query` when given: [{ id:, name:, display_name:, email: }].
    def members(team_id, query: nil)
      filter = { active: { eq: true } }
      if query.present?
        filter[:or] = %w[name displayName email].map { |field| { field => { containsIgnoreCase: query.to_s } } }
      end
      data = @client.query(<<~GRAPHQL, team: team_id.to_s, filter: filter)
        query($team: String!, $filter: UserFilter) {
          team(id: $team) { members(first: 100, filter: $filter) { nodes { id name displayName email app } } }
        }
      GRAPHQL
      Array(data.dig("team", "members", "nodes")).map do |u|
        { id: u["id"], name: u["name"], display_name: u["displayName"], email: u["email"], app: u["app"] == true }
      end
    end

    # By id or identifier (ENG-123).
    def issue(ref)
      data = @client.query(<<~GRAPHQL, id: ref.to_s)
        query($id: String!) { issue(id: $id) { ...IssueParts } }
        #{ISSUE}
      GRAPHQL
      normalize(data["issue"])
    end

    def issues(filter:, limit:, cursor: nil)
      data = @client.query(<<~GRAPHQL, filter: filter, first: limit, after: cursor.presence)
        query($filter: IssueFilter, $first: Int!, $after: String) {
          issues(filter: $filter, first: $first, after: $after, orderBy: updatedAt) {
            nodes { ...IssueParts } pageInfo { hasNextPage endCursor }
          }
        }
        #{ISSUE}
      GRAPHQL
      page = data["issues"].to_h
      { issues: Array(page["nodes"]).map { |raw| normalize(raw) },
        next_cursor: page.dig("pageInfo", "hasNextPage") ? page.dig("pageInfo", "endCursor") : nil }
    end

    def create_issue(input)
      data = @client.mutate(<<~GRAPHQL, input: input)
        mutation($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { ...IssueParts } } }
        #{ISSUE}
      GRAPHQL
      normalize(data.dig("issueCreate", "issue")) || raise(Trackers::Error.new("Linear did not create the issue", code: "provider_error"))
    end

    def update_issue(id, input)
      data = @client.mutate(<<~GRAPHQL, id: id.to_s, input: input)
        mutation($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success issue { ...IssueParts } } }
        #{ISSUE}
      GRAPHQL
      normalize(data.dig("issueUpdate", "issue")) || raise(Trackers::Error.new("Linear did not update the issue", code: "provider_error"))
    end

    def comments(issue_id, limit:, cursor: nil)
      data = @client.query(<<~GRAPHQL, id: issue_id.to_s, first: limit, after: cursor.presence)
        query($id: String!, $first: Int!, $after: String) {
          issue(id: $id) { comments(first: $first, after: $after) { nodes { #{COMMENT} } pageInfo { hasNextPage endCursor } } }
        }
      GRAPHQL
      page = data.dig("issue", "comments").to_h
      { comments: Array(page["nodes"]).map { |c| comment(c) },
        next_cursor: page.dig("pageInfo", "hasNextPage") ? page.dig("pageInfo", "endCursor") : nil }
    end

    def create_comment(issue_id, body)
      data = @client.mutate(<<~GRAPHQL, input: { issueId: issue_id.to_s, body: body.to_s })
        mutation($input: CommentCreateInput!) { commentCreate(input: $input) { success comment { #{COMMENT} } } }
      GRAPHQL
      raw = data.dig("commentCreate", "comment")
      raise Trackers::Error.new("Linear did not add the comment", code: "provider_error") if raw.blank?

      comment(raw)
    end

    # Only a workspace admin's key may manage webhooks. Answers the webhook id.
    def create_webhook(url:, team_id:, secret:, label:)
      data = @client.mutate(<<~GRAPHQL, input: { url: url, teamId: team_id, secret: secret, label: label, resourceTypes: WEBHOOK_RESOURCES })
        mutation($input: WebhookCreateInput!) { webhookCreate(input: $input) { success webhook { id enabled } } }
      GRAPHQL
      data.dig("webhookCreate", "webhook", "id") || raise(Trackers::Error.new("Linear did not create the webhook", code: "provider_error"))
    end

    def delete_webhook(id)
      @client.mutate("mutation($id: String!) { webhookDelete(id: $id) { success } }", id: id.to_s)
      true
    rescue Trackers::Error => e
      raise unless e.code == "not_found"

      false
    end

    private

    def paged
      items = []
      cursor = nil
      MAX_PAGES.times do
        page = yield(cursor).to_h
        items.concat(Array(page["nodes"]))
        break unless page.dig("pageInfo", "hasNextPage")

        cursor = page.dig("pageInfo", "endCursor")
      end
      items
    end

    def normalize(raw)
      return if raw.blank? || raw["id"].blank?

      assignee = raw["assignee"]
      {
        id: raw["id"], key: raw["identifier"], number: raw["number"], title: raw["title"], description: raw["description"],
        url: raw["url"], priority: raw["priority"], updated_at: raw["updatedAt"],
        team_id: raw.dig("team", "id"), team_key: raw.dig("team", "key"),
        state: raw["state"] && { id: raw.dig("state", "id"), name: raw.dig("state", "name"), type: raw.dig("state", "type") },
        assignee: assignee && { id: assignee["id"], name: assignee["name"], display_name: assignee["displayName"], email: assignee["email"] },
        labels: Array(raw.dig("labels", "nodes")).map { |l| { id: l["id"], name: l["name"] } }
      }
    end

    def comment(raw)
      { id: raw["id"], body: raw["body"], created_at: raw["createdAt"],
        author: raw.dig("user", "displayName") || raw.dig("user", "name") || raw.dig("botActor", "name") }
    end
  end
end
