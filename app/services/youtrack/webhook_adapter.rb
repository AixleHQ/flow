# frozen_string_literal: true

module Youtrack
  class WebhookAdapter < Webhooks::ProviderAdapter
    self.provider = :youtrack
    TEXT_LIMIT = 500
    EVENT_TYPES = { "issueCreated" => "youtrack.issue.created", "commentAdded" => "youtrack.comment.mentioned" }.freeze

    def verification_strategy = :shared_token
    def classify(payload) = EVENT_TYPES[payload["event"]] || :unsupported

    def redact(payload, event_type, integration)
      issue = payload["issue"]
      return unless issue.is_a?(Hash) && issue["id"].present? && issue["idReadable"].present?
      project = issue["project"]
      return unless project.is_a?(Hash) && project["id"].to_s == integration.youtrack_project_id
      reporter = issue["reporter"].is_a?(Hash) ? issue["reporter"] : {}
      base = { "event" => payload["event"], "timestamp" => payload["timestamp"], "issue" => {
        "id" => issue["id"], "idReadable" => issue["idReadable"], "summary" => bounded(issue["summary"]),
        "description" => bounded(issue["description"]), "project" => project.slice("id", "name", "shortName"),
        "reporter" => reporter.slice("id", "login")
      } }
      if event_type == "youtrack.comment.mentioned"
        comment = payload["comment"]
        return unless comment.is_a?(Hash) && comment["id"].present?
        author = comment["author"].is_a?(Hash) ? comment["author"] : {}
        login = integration.settings["bot_login"].to_s
        text = comment["text"].to_s
        return if login.blank? || !text.match?(/(?<![\w.-])@#{Regexp.escape(login)}(?![\w.-])/i)
        return if author["id"].to_s == integration.settings["bot_user_id"].to_s
        base["comment"] = { "id" => comment["id"], "text" => bounded(text),
          "author" => author.slice("id", "login") }
      end
      base
    end

    def dedup_key(endpoint, _event_type, redacted)
      source_id = redacted["event"] == "commentAdded" ? redacted.dig("comment", "id") : redacted.dig("issue", "id")
      Digest::SHA256.hexdigest([ endpoint.id, redacted["event"], source_id ].join(":"))
    end

    def normalize(received)
      endpoint = received.webhook_endpoint
      payload = received.raw_payload
      issue = payload["issue"].to_h
      comment = payload["comment"].to_h
      created = payload["event"] == "issueCreated"
      text = created ? [ issue["summary"], issue["description"] ].compact.join("\n\n") : comment["text"]
      { event_type: classify(payload), subject: issue["id"], data: {
        "integration_id" => endpoint.config["integration_id"], "youtrack_project_id" => issue.dig("project", "id"),
        "issue_id" => issue["id"], "issue_readable_id" => issue["idReadable"],
        "summary" => issue["summary"], "description" => issue["description"], "text" => bounded(text),
        "comment_id" => comment["id"], "actor_id" => (comment["author"] || issue["reporter"]).to_h["id"],
        "actor_login" => (comment["author"] || issue["reporter"]).to_h["login"], "occurred_at" => payload["timestamp"]
      }.compact }
    end

    def run_context(event, task)
      data = event.data.slice("integration_id", "youtrack_project_id", "issue_id", "issue_readable_id",
        "comment_id", "actor_id", "actor_login", "summary", "description", "text", "occurred_at")
      if task
        data["linked_task"] = { "id" => task.id, "title" => task.title, "column" => task.board_column&.name,
          "archived" => task.archived?, "description" => bounded(task.description) }
      end
      { "youtrack" => data.compact }
    end

    private

    def bounded(value) = value.to_s.truncate(TEXT_LIMIT, omission: "… [truncated]")
  end
end
