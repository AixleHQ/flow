# frozen_string_literal: true

module ContextBuilders
  # Tells the agent which integrations it may act through (docs/design/session-integrations.md §5.2):
  # name, provider and id, so it can pass the id as `integration_id`. Only the providers whose
  # tools take an integration are listed; repositories keep their own table. Nothing secret:
  # no credentials and no URL, only the host a Coder integration points at.
  class Integrations < Base
    def applicable?
      listed.any?
    end

    def build
      [ section(tag: "available-integrations", priority: :info, content: lines.join("\n")) ]
    end

    private

    def listed
      @listed ||= session.integrations.attachable.order(:id).to_a
    end

    def lines
      rows = [ "## Available Integrations", "", "| ID | Name | Provider | Notes |", "|---|---|---|---|" ]
      listed.each do |integration|
        rows << "| #{integration.id} | #{cell(integration.name)} | #{integration.provider} | #{cell(notes(integration))} |"
      end
      rows << ""
      rows << "Pass the integration **ID** as `integration_id` to tools that act through an integration."
    end

    def notes(integration)
      case integration.provider.to_s
      when "coder"
        [ integration.coder_host, ("template #{integration.coder_default_template}" if integration.coder_default_template.present?) ]
      when "azure_devops"
        [ integration.azure_organization_slug ]
      when "slack", "teams"
        [ integration.chat_workspace_name ]
      end.to_a.compact.join(", ").presence || "—"
    end

    def cell(text)
      text.to_s.gsub("|", "\\|").tr("\n", " ")
    end
  end
end
