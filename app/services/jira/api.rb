# frozen_string_literal: true

module Jira
  # The Jira Cloud endpoints Aixle uses, one method each, answering with plain
  # hashes. REST v2 throughout except webhooks: v2 takes and returns
  # descriptions and comments as text, v3 only as Atlassian Document Format.
  class Api
    ISSUE_FIELDS = %w[
      summary description issuetype status project assignee labels priority duedate parent components created updated
    ].join(",").freeze
    PAGE_LIMIT = 100
    MAX_PAGES = 10

    def self.for(integration)
      new(Client.new(cloud_id: integration.settings.to_h["cloud_id"], credential: Credential.new(integration)))
    end

    def initialize(client)
      @client = client
    end

    def myself
      user(@client.get("api", "2", "myself"))
    end

    # Projects this connection can browse: [{ id:, key:, name: }].
    def projects(query: nil)
      paged_values("api", "2", "project", "search", params: { query: query.presence, orderBy: "name" })
        .map { |p| { id: p["id"].to_s, key: p["key"], name: p["name"] } }
    end

    def project(id_or_key)
      raw = @client.get("api", "2", "project", id_or_key.to_s)
      { id: raw["id"].to_s, key: raw["key"], name: raw["name"],
        issue_types: Array(raw["issueTypes"]).map { |t| { id: t["id"].to_s, name: t["name"], subtask: t["subtask"] == true } } }
    end

    # The workflow statuses of each issue type: [{ issue_type:, statuses: [{ id:, name:, category: }] }].
    def statuses(project_id)
      Array(@client.get("api", "2", "project", project_id.to_s, "statuses")).map do |type|
        { issue_type: type["name"], statuses: Array(type["statuses"]).map { |s| status(s) } }
      end
    end

    def boards(project_id)
      paged_values("agile", "1.0", "board", params: { projectKeyOrId: project_id.to_s })
        .map { |b| { id: b["id"].to_s, name: b["name"], type: b["type"] } }
    end

    # A board's columns, left to right, with the status ids each one holds.
    def board_columns(board_id)
      config = @client.get("agile", "1.0", "board", board_id.to_s, "configuration")
      Array(config.dig("columnConfig", "columns")).map do |column|
        { name: column["name"], status_ids: Array(column["statuses"]).map { |s| s["id"].to_s } }
      end
    end

    def issue(id_or_key)
      normalize_issue(@client.get("api", "2", "issue", id_or_key.to_s, params: { fields: ISSUE_FIELDS }))
    end

    # { issues:, next_cursor: } — Jira's enhanced search pages by token.
    def search(jql:, limit: 50, cursor: nil)
      raw = @client.get("api", "2", "search", "jql",
                        params: { jql: jql, maxResults: limit, nextPageToken: cursor.presence, fields: ISSUE_FIELDS })
      { issues: Array(raw["issues"]).map { |i| normalize_issue(i) }, next_cursor: raw["nextPageToken"].presence }
    end

    def create_issue(fields)
      raw = @client.post("api", "2", "issue", body: { fields: fields })
      { id: raw["id"].to_s, key: raw["key"] }
    end

    def update_issue(id, fields: {}, update: {})
      body = { fields: fields.presence, update: update.presence }.compact
      @client.put("api", "2", "issue", id.to_s, body: body)
      nil
    end

    def transitions(id)
      Array(@client.get("api", "2", "issue", id.to_s, "transitions")["transitions"]).map do |t|
        { id: t["id"].to_s, name: t["name"], to: status(t["to"].to_h) }
      end
    end

    def transition(id, transition_id)
      @client.post("api", "2", "issue", id.to_s, "transitions", body: { transition: { id: transition_id.to_s } })
      nil
    end

    # `account_id` nil unassigns.
    def assign(id, account_id)
      @client.put("api", "2", "issue", id.to_s, "assignee", body: { accountId: account_id })
      nil
    end

    # { comments:, next_cursor: }, oldest first. The cursor is the next offset.
    def comments(id, limit: 50, cursor: nil)
      start = cursor.to_i
      raw = @client.get("api", "2", "issue", id.to_s, "comment", params: { startAt: start, maxResults: limit, orderBy: "created" })
      list = Array(raw["comments"]).map { |c| comment(c) }
      finished = start + list.size >= raw["total"].to_i || list.empty?
      { comments: list, next_cursor: finished ? nil : (start + list.size).to_s }
    end

    def add_comment(id, body)
      comment(@client.post("api", "2", "issue", id.to_s, "comment", body: { body: body }))
    end

    def assignable_users(project_key:, query:)
      Array(@client.get("api", "2", "user", "assignable", "search", params: { project: project_key, query: query, maxResults: 20 }))
        .map { |u| user(u) }
    end

    # Registers one dynamic webhook; its id, or a validation error naming why not.
    def register_webhook(url:, jql:, events:)
      raw = @client.post("api", "3", "webhook", body: { url: url, webhooks: [ { jqlFilter: jql, events: events } ] })
      result = Array(raw["webhookRegistrationResult"]).first.to_h
      return result["createdWebhookId"].to_s if result["createdWebhookId"].present?

      raise Error.new("Jira did not register the webhook: #{Array(result['errors']).join('; ').presence || 'no reason given'}",
                      code: "validation_failed")
    end

    # This app's webhooks on the site for this user: [{ id:, jql:, events:, expires_at: }].
    def webhooks
      paged_values("api", "3", "webhook").map do |w|
        { id: w["id"].to_s, jql: w["jqlFilter"], events: Array(w["events"]), expires_at: w["expirationDate"] }
      end
    end

    # The new expiry.
    def refresh_webhooks(ids)
      raw = @client.put("api", "3", "webhook", "refresh", body: { webhookIds: ids.map(&:to_i) })
      raw["expirationDate"].presence && Time.zone.parse(raw["expirationDate"].to_s)
    end

    def delete_webhooks(ids)
      return if ids.empty?

      @client.request_delete("api", "3", "webhook", body: { webhookIds: ids.map(&:to_i) })
      nil
    end

    private

    # Jira's offset pagination ({ values:, isLast: }), bounded.
    def paged_values(*segments, params: {})
      out = []
      MAX_PAGES.times do
        raw = @client.get(*segments, params: params.merge(startAt: out.size, maxResults: PAGE_LIMIT))
        values = Array(raw.is_a?(Hash) ? raw["values"] : raw)
        out.concat(values)
        break if !raw.is_a?(Hash) || raw["isLast"] != false || values.empty?
      end
      out
    end

    def normalize_issue(raw)
      fields = raw["fields"].to_h
      {
        id: raw["id"].to_s, key: raw["key"], summary: fields["summary"], description: fields["description"],
        type: fields.dig("issuetype", "name"), status: fields["status"] && status(fields["status"]),
        project: { id: fields.dig("project", "id").to_s, key: fields.dig("project", "key") },
        assignee: fields["assignee"] && user(fields["assignee"]), labels: Array(fields["labels"]),
        priority: fields.dig("priority", "name"), due_date: fields["duedate"], parent: fields.dig("parent", "key"),
        components: Array(fields["components"]).map { |c| c["name"] }, created_at: fields["created"],
        updated_at: fields["updated"]
      }
    end

    def status(raw)
      { id: raw["id"].to_s, name: raw["name"], category: raw.dig("statusCategory", "key") }
    end

    def user(raw)
      { id: raw["accountId"], name: raw["displayName"], email: raw["emailAddress"].presence }.compact
    end

    def comment(raw)
      { id: raw["id"].to_s, author: raw.dig("author", "displayName"), body: raw["body"], created_at: raw["created"] }
    end
  end
end
