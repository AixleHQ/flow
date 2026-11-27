# frozen_string_literal: true

module InternalTools
  module Concerns
    # The messenger-neutral side of the chat_* tools: which messenger a call
    # talks to, which conversation and thread it means, and the checks a rich
    # payload has to pass. Slack's own plumbing comes from SlackContext.
    module ChatContext
      ADAPTIVE_CARD_GUIDE = "Adaptive Card JSON (version 1.5 or lower) for Microsoft Teams: " \
                            "{\"type\":\"AdaptiveCard\",\"version\":\"1.5\",\"body\":[...],\"actions\":[...]}. " \
                            "Action.OpenUrl and Action.ShowCard work; Action.Submit and Action.Execute are " \
                            "rejected, since nothing here receives their clicks yet. Keep `text` set as well."
      INTERACTIVE_ACTIONS = %w[Action.Submit Action.Execute].freeze

      INTEGRATION_ID_SCHEMA = {
        type: "integer",
        description: "The Slack or Teams integration to act through (the ID in this session's Available Integrations). " \
                     "Not needed in a conversation the run came from, or when the session has exactly one integration " \
                     "of that messenger."
      }.freeze

      private

      # The active installs of `provider` attached to this session (docs/design/session-integrations.md
      # §5.3), never the project's.
      def attached_chat_installs(provider)
        session ? session.integrations.active.where(provider: provider) : Integration.none
      end

      # The attached installs of `provider` this call may use: all of them, or the one named by
      # `integration_id`. → [relation, error]
      def chat_install_scope(provider)
        attached = attached_chat_installs(provider)
        return [ attached, nil ] if params[:integration_id].blank?

        id = Integer(params[:integration_id].to_s, 10)
        named = attached.where(id: id)
        return [ named, nil ] if named.exists?

        [ nil, error("integration_id #{params[:integration_id]} is not a #{provider} integration attached to this session. " \
                     "#{attached_chat_hint(provider)}") ]
      rescue ArgumentError
        [ nil, error("integration_id must be an integer. #{attached_chat_hint(provider)}") ]
      end

      def attached_chat_hint(provider)
        rows = attached_chat_installs(provider).order(:id).map { |i| "#{i.id} (#{i.chat_workspace_name})" }
        rows.any? ? "Attached #{provider} integrations: #{rows.join('; ')}." : "No #{provider} integration is attached to this session."
      end

      def chat_origin
        Chat.origin(workflow_run).to_h
      end

      # The messenger named, the one the run came from, or the only one connected.
      def chat_provider
        named = params[:provider].presence || chat_origin["provider"]
        return [ named, nil ] if named.present? && Chat::PROVIDERS.key?(named.to_s)
        return [ nil, error("Unknown provider #{named.inspect}: use slack or teams") ] if named.present?

        connected = session ? (session.integrations.active.distinct.pluck(:provider).map(&:to_s) & Chat::PROVIDERS.keys).sort : []
        return [ connected.first, nil ] if connected.one?

        [ nil, error("Name the messenger: pass `provider` (#{connected.join(' or ').presence || 'none is connected'})") ]
      end

      def teams_target
        return [ nil, error("This tool needs a project — the session has none") ] if project.nil?

        scope, scope_error = chat_install_scope("teams")
        return [ nil, scope_error ] if scope_error

        conversation, message = Chat::TargetResolver.teams(project, params[:conversation], chat_origin, within: scope)
        [ conversation, message && error(message) ]
      end

      # The thread named, else — in the conversation the run came from — the
      # thread it came from.
      def teams_thread(conversation)
        return params[:thread].to_s if params[:thread].present?

        origin = chat_origin
        origin["thread_id"] if origin["provider"] == "teams" && origin.dig("conversation", "id") == conversation.external_id
      end

      def adaptive_card
        card = params[:adaptive_card]
        return [ nil, nil ] if card.blank?
        return [ nil, error("`adaptive_card` must be an Adaptive Card object") ] unless card.respond_to?(:to_h)

        card = card.to_h.deep_stringify_keys
        return [ nil, error("`adaptive_card` needs \"type\": \"AdaptiveCard\"") ] unless card["type"] == "AdaptiveCard"
        if Gem::Version.new(card["version"].presence || "1.0") > Gem::Version.new("1.5")
          return [ nil, error("Teams bots render Adaptive Cards up to version 1.5") ]
        end

        interactive = interactive_action(card)
        return [ nil, error("#{interactive} needs an endpoint for its clicks that this deployment does not run yet. " \
                            "Use Action.OpenUrl, or ask for a reply in the thread.") ] if interactive

        [ card, nil ]
      rescue ArgumentError
        [ nil, error("`adaptive_card` has an unreadable version") ]
      end

      def interactive_action(node)
        case node
        when Hash then INTERACTIVE_ACTIONS.find { |type| node["type"] == type } || node.values.lazy.filter_map { |v| interactive_action(v) }.first
        when Array then node.lazy.filter_map { |v| interactive_action(v) }.first
        end
      end

      def slack_conversation(integration, channel)
        integration && ChatConversation.in_workspace_of(integration.id).find_by(external_id: channel.to_s)
      end

      def remember_message(conversation, message_id)
        ChatMessage.record!(conversation: conversation, message_id: message_id, company_id: project&.company_id)
      end

      # In a channel several companies share, the bot's messages are not all this one's.
      def foreign_message(conversation, message_id)
        return nil unless ChatMessage.foreign?(conversation: conversation, message_id: message_id, company_id: project&.company_id)

        error("Message #{message_id} was not posted for #{project.company.name} — in a channel several companies " \
              "share, a run changes only its own company's messages")
      end

      # A payload for the other messenger is refused by name, never dropped.
      def wrong_payload(provider)
        if provider == "slack" && params[:adaptive_card].present?
          error("`adaptive_card` is for Microsoft Teams; Slack takes `slack_blocks`")
        elsif provider == "teams" && params[:slack_blocks].present?
          error("`slack_blocks` is for Slack; Microsoft Teams takes `adaptive_card`")
        end
      end

      # What Teams said no to, in terms an agent can act on.
      def teams_failure(err)
        case err.status.to_i
        when 429 then error({ error: "rate_limited", retry_after: err.retry_after || 5 }.to_json)
        when 413 then error("The message is too large for Teams — send the content as a file instead")
        when 403, 404 then error("Teams refused: the app is not in that conversation, or the message is not the bot's own")
        else error("Teams rejected the request: #{err.message}")
        end
      end

      # Markdown as Slack renders it: a markdown block, with the text as the
      # notification line. Past the block's limit, the text alone.
      def slack_markdown_blocks(text)
        return [] if text.blank? || text.length > 12_000

        [ { "type" => "markdown", "text" => text } ]
      end
    end
  end
end
