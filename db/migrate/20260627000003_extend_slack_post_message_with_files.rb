# frozen_string_literal: true

# Updates the slack_post_message platform tool so it accepts optional file
# attachments (text and/or files, sent as one Slack message). Seeds run on deploy
# via db:seed, but a migration guarantees the schema change lands on existing
# environments too. Idempotent.
class ExtendSlackPostMessageWithFiles < ActiveRecord::Migration[8.0]
  class MigrationTool < ActiveRecord::Base
    self.table_name = "tools"
  end

  INPUT_SCHEMA = {
    "type" => "object",
    "properties" => {
      "text" => { "type" => "string", "description" => "Message text. Optional when files are provided." },
      "files" => {
        "type" => "array",
        "description" => "Optional file attachments, sent in the SAME message as the text.",
        "items" => {
          "type" => "object",
          "properties" => {
            "filename" => { "type" => "string", "description" => "File name, e.g. fizzbuzz.rb" },
            "content" => { "type" => "string", "description" => "Full text content of the file" },
            "title" => { "type" => "string", "description" => "Optional display title (defaults to filename)" }
          },
          "required" => %w[filename content]
        }
      },
      "channel" => { "type" => "string", "description" => "Channel ID. Defaults to the triggering channel for Slack-started runs." },
      "thread_ts" => { "type" => "string", "description" => "Thread timestamp to reply into. Defaults to the triggering thread." }
    },
    "required" => []
  }.freeze

  def up
    tool = MigrationTool.find_or_initialize_by(name: "slack_post_message")
    tool.kind ||= "workflow"
    tool.execution_mode ||= "app"
    tool.enabled = true if tool.enabled.nil?
    tool.requires_integration = "slack"
    tool.display_name = "Slack Post Message"
    tool.description = "Send a Slack message from this workflow. `text` and `files` are both optional but " \
                       "at least one is required — text only, files only, or both arrive as ONE message. " \
                       "Omit channel/thread to reply in the channel/thread that triggered the run. " \
                       "Requires a Slack integration on the project."
    tool.input_schema = INPUT_SCHEMA
    tool.save!
  end

  def down
    # Schema-only data change; nothing to reverse safely.
  end
end
