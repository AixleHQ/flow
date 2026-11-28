# frozen_string_literal: true

module InternalTools
  module Concerns
    # SlackContext — the Slack side of the chat_* tools: which workspace install
    # a call talks to, and the channel/thread the run was started from.
    #
    # Nothing here needs a workflow: the install is resolved from the session's
    # PROJECT. What a session with no run behind it loses is the trigger context,
    # so it has to name the channel itself. The install can still be missing — a
    # workspace disconnected mid-run — and the guards here cover that.
    module SlackContext
      # What an agent needs to know to write `blocks` without a round-trip through
      # a Slack `invalid_blocks` error: the block types that work on the message
      # surface, their size caps, and the two formatting dialects. Shared by every
      # tool that accepts blocks, so the guidance can never drift between them.
      BLOCK_KIT_GUIDE = <<~GUIDE.freeze
        Block Kit array, max 50 blocks. Message-surface types worth using:
        - {"type":"markdown","text":"..."} — real Markdown: headings, tables, ordered lists,
          [links](url), fenced code. The easiest path, and usually the right one. 12000 chars
          across all markdown blocks in the message; every heading level renders one size and
          images become links.
        - {"type":"section","text":{"type":"mrkdwn","text":"..."}} — mrkdwn, max 3000 chars.
          Optional "fields": up to 10 text objects of 2000 chars, laid out in two columns.
        - {"type":"header","text":{"type":"plain_text","text":"..."}} — max 150 chars, plain_text only.
        - {"type":"context","elements":[...]} — up to 10 small text/image elements, for footnotes.
        - {"type":"divider"} — a horizontal rule.
        - {"type":"image","image_url":"https://...","alt_text":"..."} — png/jpg/gif at a PUBLIC url
          (max 3000 chars; alt_text max 2000). To show a file you just produced, attach it through
          `files` instead — a container path is not reachable by Slack.
        mrkdwn is NOT Markdown: *bold*, _italic_, ~strike~, `code`, ```block```, > quote,
        <https://url|label>, <@U123>, <#C123>. [label](url) does NOT render in an mrkdwn text
        object — use a markdown block if you want Markdown syntax.
        Interactive blocks (actions/input, buttons, selects) are rejected: the Slack interactivity
        endpoint serves only the Run workflow shortcut and its form, so a click would go nowhere.
        Keep `text` set alongside blocks — it is the notification and fallback line.
      GUIDE

      # Blocks whose whole point is a click Slack would deliver to an interactivity
      # request URL this deployment does not expose.
      INTERACTIVE_BLOCK_TYPES = %w[actions input].freeze

      MAX_BLOCKS = 50

      private

      # Where a Slack-started run came from, in Slack's own terms. Empty for a run
      # that did not start from Slack, and for a session with no run behind it.
      def slack_context
        origin = Chat.origin(workflow_run).to_h
        return {} unless origin["provider"] == Chat::SlackProvider::KEY

        { "channel" => origin.dig("conversation", "id"), "thread_ts" => origin["thread_id"],
          "team" => origin["workspace_id"], "integration_id" => origin["integration_id"] }.compact
      end

      # The install a call without a channel of its own acts through, from this session's set:
      # the workspace that started the run, else the one named by `integration_id`, else the
      # only Slack install attached. → [integration, error]
      def slack_integration
        return [ nil, error("This tool needs a project — the session has none") ] if project.nil?

        origin = attached_chat_installs("slack").find_by(id: slack_context["integration_id"].to_i)
        return [ origin, nil ] if origin

        scope, scope_error = chat_install_scope("slack")
        return [ nil, scope_error ] if scope_error
        return [ scope.first, nil ] if scope.one?

        [ nil, error(scope.none? ? "Slack is not attached to this session. #{attached_chat_hint('slack')}" :
                                   "This session has several Slack integrations: pass `integration_id`. #{attached_chat_hint('slack')}") ]
      end

      # The install and channel a call acts on: the thread the run came from by
      # default, otherwise a channel connected to the project's company
      # (Chat::ChannelAccess) in a workspace attached to this session.
      # Returns [integration, channel, error].
      def resolve_slack_target(explicit_channel)
        return [ nil, nil, error("This tool needs a project — the session has none") ] if project.nil?

        origin = slack_context["channel"]
        value = explicit_channel.to_s.strip.presence
        return slack_origin_target(origin) if origin.present? && (value.nil? || value == origin)

        if value.nil?
          return [ nil, nil, error("No channel given. Only a run started from Slack has one to " \
                                   "fall back on — pass `conversation` explicitly.") ]
        end

        scope, scope_error = chat_install_scope("slack")
        return [ nil, nil, scope_error ] if scope_error

        conversation = Chat::ChannelAccess.find(project, "slack", value, within: scope)
        if conversation.nil?
          return [ nil, nil, error(Chat::ChannelAccess.not_connected(project, "slack", value, within: scope)) ]
        end

        [ Chat::ChannelAccess.install_for(project, conversation, within: scope), conversation.external_id, nil ]
      end

      def slack_origin_target(channel)
        integration, integration_error = slack_integration
        return [ nil, nil, integration_error ] if integration_error

        [ integration, channel, nil ]
      end

      def slack_bot_token(integration)
        integration.credentials_data["bot_token"]
      end

      # A Slack call whose failure is the agent's to see and act on — unlike
      # Slack::Notifier, which swallows errors so a Slack outage can never fail a
      # run. Returns [response, error]; the Slack error code (channel_not_found,
      # message_not_found, invalid_blocks, ...) is passed through verbatim, since
      # that is what tells the agent which retry is worth making.
      def slack_call
        [ yield, nil ]
      rescue Slack::Client::RateLimited => e
        [ nil, error({ error: "rate_limited", retry_after: e.retry_after }.to_json) ]
      rescue Slack::Client::Error => e
        [ nil, error("Slack rejected the request: #{e.message}") ]
      end

      # Normalizes the `blocks` param and catches the mistakes worth catching
      # before they cost a Slack round-trip: a non-array, more than 50 blocks, an
      # entry that is not a typed block object, or an interactive block nothing in
      # this deployment could respond to. Returns [blocks, error]; blocks is [] when
      # none were given, and nil when the entry was rejected.
      def build_blocks(raw = params[:blocks])
        return [ [], nil ] if raw.blank?
        return [ nil, error("`blocks` must be an array of Block Kit block objects") ] unless raw.is_a?(Array)
        return [ nil, error("`blocks` is capped at #{MAX_BLOCKS} blocks per message") ] if raw.size > MAX_BLOCKS

        blocks = raw.map { |b| b.respond_to?(:to_h) ? b.to_h.with_indifferent_access : b }
        untyped = blocks.each_index.reject { |i| blocks[i].is_a?(Hash) && blocks[i][:type].present? }
        return [ nil, error("blocks[#{untyped.first}] is not a block object with a `type`") ] if untyped.any?

        interactive = blocks.select { |b| INTERACTIVE_BLOCK_TYPES.include?(b[:type].to_s) }
        if interactive.any?
          return [ nil, error("Block type `#{interactive.first[:type]}` needs a Slack interactivity " \
                              "handler, and the endpoint serves only the Run workflow shortcut — its clicks would go nowhere. " \
                              "Post the options as text and ask for a reply instead.") ]
        end

        [ blocks, nil ]
      end
    end
  end
end
