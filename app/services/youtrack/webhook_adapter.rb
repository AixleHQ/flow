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
      integration = Integration.find_by(id: endpoint.config["integration_id"])
      resource = ExternalResource.new(type: "youtrack_issue", external_instance: integration&.youtrack_base_url,
        data: { "readable_id" => issue["idReadable"] })
      created = payload["event"] == "issueCreated"
      text = created ? [ issue["summary"], issue["description"] ].compact.join("\n\n") : comment["text"]
      { event_type: classify(payload), subject: issue["id"], data: {
        "integration_id" => endpoint.config["integration_id"], "youtrack_project_id" => issue.dig("project", "id"),
        "issue_id" => issue["id"], "issue_readable_id" => issue["idReadable"], "issue_url" => integration && resource.url,
        "source_event" => payload["event"],
        "summary" => issue["summary"], "description" => issue["description"], "text" => bounded(text),
        "comment_id" => comment["id"], "actor_id" => (comment["author"] || issue["reporter"]).to_h["id"],
        "actor_login" => (comment["author"] || issue["reporter"]).to_h["login"], "occurred_at" => payload["timestamp"]
      }.compact }
    end

    def run_context(event, task)
      data = event.data.slice("integration_id", "youtrack_project_id", "issue_id", "issue_readable_id",
        "issue_url", "source_event", "comment_id", "actor_id", "actor_login", "summary", "description", "text", "occurred_at")
      if task
        data["linked_task"] = { "id" => task.id, "title" => task.title, "column" => task.board_column&.name,
          "archived" => task.archived?, "description" => bounded(task.description),
          "url" => Rails.application.routes.url_helpers.company_project_board_url(
            task.board.project_id, task: task.id, host: Settings.domain, protocol: Settings.protocol) }
      end
      { "youtrack" => data.compact }
    end

    def record_subject!(task, binding, event)
      integration = binding.integration
      task.external_resources.create!(type: "youtrack_issue", external_instance: integration.youtrack_base_url,
        external_id: event.data["issue_id"], data: { "readable_id" => event.data["issue_readable_id"],
          "youtrack_project_id" => event.data["youtrack_project_id"], "workflow_id" => binding.workflow_id,
          "binding_id" => binding.id, "created_via_integration_id" => integration.id }.compact)
    end

    def find_subject(binding, event)
      return unless binding.integration
      links = ExternalResource.joins(board_task: :board)
        .where(type: "youtrack_issue", external_instance: binding.integration.youtrack_base_url,
          external_id: event.data["issue_id"], boards: { project_id: binding.project_id })
        .merge(BoardTask.active).order(:created_at, :id)
      same_workflow = links.select { |link| link.data["workflow_id"].to_s == binding.workflow_id.to_s }
      return same_workflow.first.board_task if same_workflow.any?
      return links.first.board_task if links.one?
      if links.many?
        Rails.logger.info("[YouTrack] ambiguous_external_subject binding_id=#{binding.id} event_id=#{event.id}")
      end
      nil
    end

    private

    def bounded(value) = value.to_s.truncate(TEXT_LIMIT, omission: "… [truncated]")
  end
end
