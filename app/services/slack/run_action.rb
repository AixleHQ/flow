# frozen_string_literal: true

module Slack
  # Starting a workflow yourself from Slack (docs/design/teams-integration.md §21):
  # the "Run workflow" message shortcut and `/<command> run` open a modal of the
  # workflows the linked person may start; submitting it starts the run as them.
  # `/<command> status` lists the runs started in the channel. Slack waits three
  # seconds for each answer.
  module RunAction
    CALLBACK = "run_workflow"
    SUBCOMMANDS = %r{\A(run|status)(?:\s+(.*))?\z}im
    STATES = {
      "pending" => ":hourglass_flowing_sand: Accepted", "running" => ":arrow_forward: Running",
      "paused" => ":arrow_forward: Running", "completed" => ":white_check_mark: Completed",
      "failed" => ":x: Failed", "cancelled" => ":black_square_for_stop: Cancelled"
    }.freeze

    module_function

    # A message shortcut: the modal, or why there is none, opened for the person.
    def shortcut(integration, payload)
      message = payload["message"].to_h
      context = { "channel" => payload.dig("channel", "id"), "message_ts" => message["ts"],
                  "thread_ts" => message["thread_ts"], "text" => message["text"].to_s.truncate(2000) }
      open_view(integration, payload["trigger_id"], view_for(integration, payload.dig("team", "id"),
                                                            payload.dig("user", "id"), context))
    end

    # A slash command: `run` opens the modal, `status` answers in the channel,
    # only to the person. Returns the JSON Slack shows them, or nil for nothing.
    def command(integration, params)
      name, rest = params[:text].to_s.strip.match(SUBCOMMANDS)&.captures
      team, user_id, channel = params.values_at(:team_id, :user_id, :channel_id)
      case name&.downcase
      when "run"
        open_view(integration, params[:trigger_id], view_for(integration, team, user_id,
                                                             { "channel" => channel, "notes" => rest.to_s.strip }))
        nil
      when "status" then ephemeral(status_blocks(integration, team, user_id, channel))
      else ephemeral([ section("`#{params[:command]} run` starts a workflow you can run, as you. " \
                               "`#{params[:command]} status` lists the runs started in this channel.") ])
      end
    end

    # The modal's submission: start the chosen workflow, or say why not on the modal.
    def submit(integration, payload)
      view = payload["view"].to_h
      context = JSON.parse(view["private_metadata"].presence || "{}")
      team, user_id = payload.dig("team", "id"), payload.dig("user", "id")
      user = Sender.user(team, user_id)
      return errors("Link your Aixle account first: run the shortcut again.") if user.nil?

      values = view.dig("state", "values").to_h
      entry = Chat::RunCatalog.find(user, integration, values.dig("workflow", "workflow", "selected_option", "value"))
      return errors("You can't start that workflow from Slack (any more).") if entry.nil?

      start(integration, user, entry, team, user_id, context, values.dig("notes", "notes", "value"), view["id"])
      {}
    rescue Chat::RunStarter::Refused => e
      errors(e.message)
    end

    # From a message the run answers in that message's thread; from the command
    # it gets a thread of its own, opened by a line saying who started what.
    def start(integration, user, entry, team, user_id, context, notes, view_id)
      dedup_key = "slack-view:#{view_id}"
      thread_ts = context["thread_ts"].presence || context["message_ts"].presence ||
                  Chat::RunStarter.recorded(dedup_key)&.data&.dig("thread_ts")
      opened = thread_ts.nil?
      thread_ts = open_thread(integration, context["channel"], user_id, entry) if opened
      text = [ context["text"].presence, (notes.presence && "Notes: #{notes}") ].compact.join("\n\n").presence ||
             "#{entry.workflow.name}, started from Slack"
      Chat::RunStarter.start!(
        integration: integration, user: user, entry: entry, dedup_key: dedup_key,
        source: "slack:slack-team-#{team}", subject: context["channel"],
        data: {
          "provider" => Chat::SlackProvider::KEY, "integration_id" => integration.id, "workspace" => { "id" => team },
          "conversation" => { "id" => context["channel"], "type" => conversation_type(context["channel"]) },
          "channel" => context["channel"], "team" => team, "user" => user_id,
          "thread_id" => thread_ts, "thread_ts" => thread_ts, "message_id" => context["message_ts"] || thread_ts,
          "ts" => context["message_ts"] || thread_ts, "actor" => { "id" => user_id, "aixle_user_id" => user.id },
          "text" => text
        }
      )
    rescue Chat::RunStarter::Refused
      close_thread(integration, context["channel"], thread_ts) if opened
      raise
    end

    def view_for(integration, team, user_id, context)
      user = Sender.user(team, user_id)
      return link_view(AccountLink.url_for(integration: integration, team_id: team, user_id: user_id)) if user.nil?

      entries = Chat::RunCatalog.entries(user, integration)
      return notice_view("There is no workflow you can start from Slack in #{integration.company.name}.") if entries.empty?

      picker_view(entries, context)
    end

    def picker_view(entries, context)
      notes = { type: "plain_text_input", action_id: "notes", multiline: true, max_length: 2000,
                initial_value: context["notes"].presence }.compact
      {
        type: "modal", callback_id: CALLBACK, private_metadata: context.except("notes").compact.to_json,
        title: plain("Run workflow"), submit: plain("Run"), close: plain("Cancel"),
        blocks: [
          { type: "input", block_id: "workflow", label: plain("Workflow"),
            element: { type: "static_select", action_id: "workflow", initial_option: option(entries.first),
                       options: entries.first(100).map { |entry| option(entry) } } },
          { type: "input", block_id: "notes", optional: true, label: plain("Notes"), element: notes }
        ]
      }
    end

    def link_view(url)
      { type: "modal", callback_id: CALLBACK, title: plain("Link your account"), close: plain("Close"),
        blocks: [ section("Aixle Flow starts workflows as the Aixle user you are, with what that account may run. " \
                          "Link your Slack account once; the link works for an hour."),
                  { type: "actions", elements: [ { type: "button", text: plain("Link my Aixle account"), url: url,
                                                   action_id: "link", style: "primary" } ] } ] }
    end

    def notice_view(text)
      { type: "modal", callback_id: CALLBACK, title: plain("Aixle Flow"), close: plain("Close"), blocks: [ section(text) ] }
    end

    def status_blocks(integration, team, user_id, channel)
      user = Sender.user(team, user_id)
      if user.nil?
        url = AccountLink.url_for(integration: integration, team_id: team, user_id: user_id)
        return [ section("Link your Aixle account first: <#{url}|link my Aixle account>.") ]
      end
      return [ section("You are not a member of #{integration.company.name} in Aixle.") ] unless Chat::RunCatalog.member?(user, integration)

      runs = Chat::RecentRuns.for(user, integration, provider: Chat::SlackProvider::KEY, conversation_id: channel)
      return [ section("No runs were started from this channel in the last 30 days.") ] if runs.empty?

      lines = runs.map do |run|
        "#{STATES.fetch(run.state.to_s, run.state.to_s.humanize)} — *#{StatusCard.escape(run.workflow&.name || 'Workflow')}* " \
          "· <#{Chat::RunFailure.url(run)}|run ##{run.id}>"
      end
      [ section("*Recent runs started here*\n#{lines.join("\n")}") ]
    end

    def open_thread(integration, channel, user_id, entry)
      Client.post_message(token: token(integration), channel: channel,
                          text: ":arrow_forward: <@#{user_id}> started *#{StatusCard.escape(entry.workflow.name)}*")["ts"]
    rescue Client::Error => e
      raise Chat::RunStarter::Refused, "Aixle Flow could not post in this channel (#{e.message}). Invite it to the channel first."
    end

    # The opening line of a run that did not start says nothing true.
    def close_thread(integration, channel, ts)
      Client.delete_message(token: token(integration), channel: channel, ts: ts)
    rescue Client::Error => e
      Rails.logger.warn("[Slack::RunAction] could not remove the opening of thread #{ts}: #{e.message}")
    end

    def open_view(integration, trigger_id, view)
      Client.open_view(token: token(integration), trigger_id: trigger_id, view: view)
    rescue Client::Error => e
      Rails.logger.error("[Slack::RunAction] views.open: #{e.message}")
    end

    def token(integration) = integration.credentials_data["bot_token"]

    def conversation_type(channel) = channel.to_s.start_with?("D") ? "direct" : "channel"

    def option(entry) = { text: plain(entry.title.truncate(75)), value: entry.key }

    def plain(text) = { type: "plain_text", text: text }

    def section(text) = { type: "section", text: { type: "mrkdwn", text: text } }

    def ephemeral(blocks) = { response_type: "ephemeral", blocks: blocks, text: blocks.first.dig(:text, :text) }

    def errors(message) = { response_action: "errors", errors: { "workflow" => message.truncate(150) } }
  end
end
