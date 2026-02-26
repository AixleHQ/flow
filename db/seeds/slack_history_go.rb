# frozen_string_literal: true

module Seeds
  module SlackHistoryGo
    BINARY_PATH = Rails.root.join("docker/tools/slack_history/slack_history")

    def self.seed!(company)
      # Migrate from system back to company-scoped custom
      Tool.where(name: "slack_history", kind: "system").update_all(
        kind: "custom", scope_type: "Company", scope_id: company.id
      )

      tool = company.tools.find_or_initialize_by(name: "slack_history")
      tool.update!(
        display_name: "Slack History",
        description: "Fetch messages from a Slack channel for a given time range. " \
                     "Resolves user IDs to display names. " \
                     "Handles Slack rate limits with exponential backoff. " \
                     "Output: NDJSON (one enriched JSON message per line).",
        docker_image: "alpine:3.20",
        command: "/workspace/slack_history",
        kind: :custom,
        required_config_items: %w[SLACK_TOKEN SLACK_CHANNEL],
        input_schema: {
          type: "object",
          properties: {
            CHANNEL: { type: "string", description: "Slack channel ID (e.g. C03E674JKNH). Overrides SLACK_CHANNEL config." },
            SLACK_RANGE: { type: "string", description: "Time range (e.g. 24h, 7d, 1w)", default: "7d" }
          }
        }
      )

      tool.tool_files.where.not(path: "/workspace/slack_history").destroy_all

      tf = tool.tool_files.find_or_initialize_by(path: "/workspace/slack_history")
      tf.content = nil
      tf.file = File.open(BINARY_PATH, "rb")
      tf.save!

      puts "  Tool seeded: #{tool.display_name} (binary #{File.size(BINARY_PATH) / 1024}KB, company: #{company.name})"
    end
  end
end
