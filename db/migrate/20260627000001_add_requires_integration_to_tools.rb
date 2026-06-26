# frozen_string_literal: true

# Adds a per-tool integration gate and backfills the slack_post_message platform
# tool. Platform tools are seeded via db/seeds/platform_tools.rb (run on deploy by
# db:seed), but a migration guarantees the tool lands on every existing
# environment without relying on the seed step. Idempotent.
class AddRequiresIntegrationToTools < ActiveRecord::Migration[8.0]
  # Decoupled from the app Tool model so this migration keeps working regardless
  # of future model validations/callbacks.
  class MigrationTool < ActiveRecord::Base
    self.table_name = "tools"
  end

  def up
    unless column_exists?(:tools, :requires_integration)
      add_column :tools, :requires_integration, :string
    end
    MigrationTool.reset_column_information

    tool = MigrationTool.find_or_initialize_by(name: "slack_post_message")
    tool.kind = "workflow"
    tool.execution_mode = "app"
    tool.enabled = true
    tool.requires_integration = "slack"
    tool.display_name = "Slack Post Message"
    tool.description = "Post a message to Slack from this workflow. Omit channel/thread to reply in " \
                       "the channel/thread that triggered the run. Requires a Slack integration on the project."
    tool.input_schema = {
      "type" => "object",
      "properties" => {
        "text" => { "type" => "string", "description" => "Message text (required)" },
        "channel" => { "type" => "string", "description" => "Channel ID. Defaults to the triggering channel for Slack-started runs." },
        "thread_ts" => { "type" => "string", "description" => "Thread timestamp to reply into. Defaults to the triggering thread." }
      },
      "required" => [ "text" ]
    }
    tool.save!
  end

  def down
    remove_column :tools, :requires_integration if column_exists?(:tools, :requires_integration)
  end
end
