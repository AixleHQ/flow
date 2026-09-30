# frozen_string_literal: true

# Until now every session of a project with an Azure connection had the Azure
# work-item tools injected. Their replacements, the tracker_* tools, are attached
# rather than injected, so the workflows of those projects get them attached
# once here — nothing they could do before stops working. Afterwards the tools
# follow the usual rules and can be detached like any other.
class AttachTrackerToolsToAzureWorkflows < ActiveRecord::Migration[8.1]
  TRACKER_TOOLS = %w[
    tracker_list tracker_describe tracker_search_issues tracker_get_issue tracker_list_comments
    tracker_create_issue tracker_update_issue tracker_transition_issue tracker_assign_issue
    tracker_add_comment tracker_link_task
  ].freeze

  class MigrationWorkflow < ActiveRecord::Base
    self.table_name = "workflows"
  end

  def up
    project_ids = select_values(<<~SQL.squish)
      SELECT DISTINCT project_id FROM integrations WHERE provider = 'azure_devops' AND project_id IS NOT NULL
    SQL
    return if project_ids.empty?

    # The tools' shadow rows are normally materialized at boot, after
    # migrations; the ids are needed now.
    Tools::Reconciler.run!
    tool_ids = select_values(<<~SQL.squish).map(&:to_i)
      SELECT id FROM tools WHERE source = 'code' AND deleted_at IS NULL
        AND name IN (#{TRACKER_TOOLS.map { |n| connection.quote(n) }.join(', ')})
    SQL
    return if tool_ids.empty?

    MigrationWorkflow.where(scope_type: "Project", scope_id: project_ids, deleted_at: nil).find_each do |workflow|
      config = workflow.config.to_h
      current = Array(config["base_tool_ids"])
      missing = tool_ids.reject { |id| current.map(&:to_i).include?(id) }
      next if missing.empty?

      workflow.update_columns(config: config.merge("base_tool_ids" => current + missing))
    end
  end

  def down
    # Irreversible by intent: after this runs, a tracker tool in a workflow's base
    # list may have been attached by a person, and nothing records which.
  end
end
