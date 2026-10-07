# frozen_string_literal: true

module Teams
  # /run and /status (docs/design/teams-integration.md §20): asked privately, as
  # a slash command or in a 1:1 chat, and answered only to the person who asked.
  module Commands
    PATTERN = %r{\A/?(run|status)(?:\s+(.*))?\z}im
    # In a 1:1 chat every message may be a trigger's, so only the slash form or
    # the bare word is a command there.
    DIRECT_PATTERN = %r{\A(?:/(run|status)(?:\s+(.*))?|(run|status))\z}im
    # The words alone, which no Teams trigger may use as its command.
    RESERVED = %r{\A/?(run|status)\z}i
    STATUS_LIMIT = 10
    STATES = {
      "pending" => "⏳ Accepted", "running" => "▶️ Running", "paused" => "▶️ Running", "completed" => "✅ Completed",
      "failed" => "❌ Failed", "cancelled" => "⏹️ Cancelled"
    }.freeze

    module_function

    def command(event)
      data = event.data.to_h
      text = data["text"].to_s.strip
      if data["targeted"]
        match = text.match(PATTERN)
        match && [ match[1].downcase, match[2].to_s.strip ]
      elsif data.dig("conversation", "type") == "direct"
        match = text.match(DIRECT_PATTERN)
        match && [ (match[1] || match[3]).downcase, match[2].to_s.strip ]
      end
    end

    # True when the event was one of these commands and has been answered.
    def call(event)
      name, rest = command(event)
      return false if name.nil?

      data = event.data.to_h
      integration = Integration.active.find_by(id: data["integration_id"], provider: Connection::PROVIDER)
      conversation = Notifier.conversation_for(data["integration_id"], data.dig("conversation", "id"))
      return true if integration.nil? || conversation.nil?

      answer(conversation, data, name == "run" ? run_card(integration, data, rest) : status_card(integration, conversation, data))
      true
    rescue Teams::Error => e
      Rails.logger.error("[Teams::Commands] event ##{event&.id}: #{e.message}")
      true
    end

    def run_card(integration, data, notes)
      user = sender(data)
      return link_card(integration, data) if user.nil?

      entries = RunCatalog.entries(user, integration)
      return RunCards.notice("There is no workflow you can start from Teams in #{integration.company.name}.") if entries.empty?

      RunCards.picker(entries, data: {}, execute: true, notes: notes.presence)
    end

    # Only runs of projects the asker may see in Aixle: a quiet trigger's runs
    # never showed themselves in the conversation.
    def status_card(integration, conversation, data)
      user = sender(data)
      return link_card(integration, data) if user.nil?
      return RunCards.notice("You are not a member of #{integration.company.name} in Aixle.") unless RunCatalog.member?(user, integration)

      projects = RunCatalog.active_projects(integration).select { |project| project.accessible_by?(user) }
      RunCards.notice(status_text(projects.map(&:id), conversation))
    end

    def sender(data) = Sender.user(data.dig("workspace", "id"), data.dig("actor", "id"))

    def link_card(integration, data)
      RunCards.link(AccountLink.url_for(integration: integration, tenant_id: data.dig("workspace", "id"),
                                        object_id: data.dig("actor", "id")))
    end

    def status_text(project_ids, conversation)
      runs = WorkflowRun.where(project_id: project_ids, created_at: 30.days.ago..)
                        .where("shared_context -> 'chat' ->> 'provider' = ?", Chat::TeamsProvider::KEY)
                        .where("shared_context -> 'chat' -> 'conversation' ->> 'id' = ?", conversation.external_id)
                        .includes(:workflow).order(created_at: :desc).limit(STATUS_LIMIT)
      return "No runs were started from this conversation in the last 30 days." if runs.empty?

      lines = runs.map do |run|
        "- #{STATES.fetch(run.state.to_s, run.state.to_s.humanize)} — **#{Notifier.escape(run.workflow&.name || 'Workflow')}** " \
          "· [run ##{run.id}](#{Chat::RunFailure.url(run)})"
      end
      "**Recent runs started here**\n\n#{lines.join("\n")}"
    end

    # A slash command in a channel or group chat is a targeted message, so is the
    # answer; a 1:1 chat is private already.
    def answer(conversation, data, card)
      activity = { type: "message", attachments: [ RunCards.attachment(card) ] }
      if data["targeted"]
        ConnectorClient.send_targeted(conversation.teams_reference, activity, recipient: data["requester"], about: data["message_id"])
      else
        ConnectorClient.send_message(conversation.teams_reference, activity)
      end
    end
  end
end
