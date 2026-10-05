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

      private

      def chat_origin
        Chat.origin(workflow_run).to_h
      end

      # The messenger named, the one the run came from, or the only one connected.
      def chat_provider
        named = params[:provider].presence || chat_origin["provider"]
        return [ named, nil ] if named.present? && Chat::PROVIDERS.key?(named.to_s)
        return [ nil, error("Unknown provider #{named.inspect}: use slack or teams") ] if named.present?

        connected = project ? Tool.active_integration_providers(project) & Chat::PROVIDERS.keys : []
        return [ connected.first, nil ] if connected.one?

        [ nil, error("Name the messenger: pass `provider` (#{connected.join(' or ').presence || 'none is connected'})") ]
      end

      def teams_target
        return [ nil, error("This tool needs a project — the session has none") ] if project.nil?

        conversation, message = Chat::TargetResolver.teams(project, params[:conversation], chat_origin)
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
