# frozen_string_literal: true

module InternalTools
  module Concerns
    # SlackContext — shared plumbing for the Slack tools: which workspace install
    # this call talks to, and the channel/thread the run was started from.
    #
    # Every Slack tool is gated on `requires_integration :slack`, so the install
    # exists in the common case; the guards here cover the run that was launched
    # by hand, or after the workspace was disconnected mid-run.
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
        Interactive blocks (actions/input, buttons, selects) are rejected: this deployment runs no
        Slack interactivity endpoint, so a click would go nowhere.
        Keep `text` set alongside blocks — it is the notification and fallback line.
      GUIDE

      # Blocks whose whole point is a click Slack would deliver to an interactivity
      # request URL this deployment does not expose.
      INTERACTIVE_BLOCK_TYPES = %w[actions input].freeze

      MAX_BLOCKS = 50

      private

      # Reply coordinates threaded into the run by TriggerEngine#slack_run_context:
      # channel, ts, thread_ts, team, integration_id, plus the triggering message's
      # text and author. Empty for a run that did not start from Slack.
      def slack_context
        workflow_run&.shared_context.to_h["slack"] || {}
      end

      # Reply through the SAME workspace that triggered this run (its integration is
      # carried in shared_context), so with several connected workspaces the message
      # goes back to the right one. Falls back to any active install for the company
      # (e.g. a run not started from Slack).
      def slack_integration
        return nil if project.nil?

        scope = Integration.active.where(provider: :slack, company_id: project.company_id)

        if (id = slack_context["integration_id"]).present?
          by_id = scope.find_by(id: id)
          return by_id if by_id
        end

        scope.where("project_id = :pid OR project_id IS NULL", pid: project.id)
          .order(Arel.sql("project_id IS NULL"))
          .first
      end

      # The install and channel a call acts on, defaulting the channel to the one
      # that triggered the run. Returns [integration, channel, error]: on the first
      # missing half, error is a tool error naming what is absent.
      def resolve_slack_target(explicit_channel)
        integration = slack_integration
        return [ nil, nil, error("Slack is not connected for this project") ] if integration.nil?

        channel = explicit_channel.presence || slack_context["channel"]
        if channel.blank?
          return [ integration, nil, error("No channel given, and this run was not triggered from Slack") ]
        end

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
      rescue Slack::Client::Error => e
        [ nil, error("Slack rejected the request: #{e.message}") ]
      end

      # Normalizes the `blocks` param and catches the mistakes worth catching
      # before they cost a Slack round-trip: a non-array, more than 50 blocks, an
      # entry that is not a typed block object, or an interactive block nothing in
      # this deployment could respond to. Returns [blocks, error]; blocks is [] when
      # none were given, and nil when the entry was rejected.
      def build_blocks
        raw = params[:blocks]
        return [ [], nil ] if raw.blank?
        return [ nil, error("`blocks` must be an array of Block Kit block objects") ] unless raw.is_a?(Array)
        return [ nil, error("`blocks` is capped at #{MAX_BLOCKS} blocks per message") ] if raw.size > MAX_BLOCKS

        blocks = raw.map { |b| b.respond_to?(:to_h) ? b.to_h.with_indifferent_access : b }
        untyped = blocks.each_index.reject { |i| blocks[i].is_a?(Hash) && blocks[i][:type].present? }
        return [ nil, error("blocks[#{untyped.first}] is not a block object with a `type`") ] if untyped.any?

        interactive = blocks.select { |b| INTERACTIVE_BLOCK_TYPES.include?(b[:type].to_s) }
        if interactive.any?
          return [ nil, error("Block type `#{interactive.first[:type]}` needs a Slack interactivity " \
                              "endpoint this deployment does not run — its clicks would go nowhere. " \
                              "Post the options as text and ask for a reply instead.") ]
        end

        [ blocks, nil ]
      end
    end
  end
end
