# frozen_string_literal: true

module InternalTools
  # Platform tool: delete a Slack message this workflow posted, addressed by the
  # `ts` slack_post_message returned. For retracting a message that turned out to
  # be wrong or is superseded — prefer slack_update_message when the message
  # should stay and only its content changed, since a delete leaves people who
  # already read it with no correction.
  class SlackDeleteMessage < Base
    include Concerns::SlackContext

    tool do
      display_name "Slack Delete Message"
      description "Delete a Slack message this workflow posted, by its `ts` (returned by slack_post_message). Only the bot's own messages can be deleted, and the deletion is permanent. Prefer slack_update_message when the message should stay and only its content is wrong. Omit `channel` to use the channel that triggered the run."
      tags :messaging, :slack
      inject_when :workflow_step_session
      requires_integration :slack
      destructive
      input_schema({
        type: "object",
        required: %w[ts],
        properties: {
          ts: {
            type: "string",
            description: "Timestamp of the message to delete, e.g. 1700000000.000100. " \
                         "Returned by slack_post_message."
          },
          channel: {
            type: "string",
            description: "Channel ID the message lives in. Defaults to the triggering channel."
          }
        }
      })
    end

    def execute
      require_workflow_context!

      integration, channel, target_error = resolve_slack_target(params[:channel])
      return target_error if target_error

      _response, call_error = slack_call do
        Slack::Client.delete_message(
          token: slack_bot_token(integration), channel: channel, ts: params[:ts].to_s
        )
      end
      call_error || success("Deleted #{params[:ts]} from #{channel}")
    end
  end
end
