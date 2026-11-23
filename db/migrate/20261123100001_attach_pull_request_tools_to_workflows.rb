# frozen_string_literal: true

# The pull_request_* tools used to be injected into every session that held a GitHub,
# GitLab or Bitbucket repository. They are attached like other tools now, so the
# workflows that could have such a repository (those of a company or project with a
# connection to one of the three) get them attached once here: nothing they could do
# before stops working. Afterwards a workflow or a step can remove them like any
# other tool.
class AttachPullRequestToolsToWorkflows < ActiveRecord::Migration[8.1]
  PULL_REQUEST_TOOLS = %w[
    pull_request_list pull_request_get pull_request_changes pull_request_create pull_request_update
    pull_request_list_comments pull_request_add_comment pull_request_review pull_request_merge pull_request_checks
  ].freeze

  HOSTS = %w[github gitlab bitbucket].freeze

  class MigrationWorkflow < ActiveRecord::Base
    self.table_name = "workflows"
  end

  def up
    # The tools' shadow rows are normally materialized at boot, after migrations;
    # the ids are needed now.
    Tools::Reconciler.run!
    tool_ids = select_values(<<~SQL.squish).map(&:to_i)
      SELECT id FROM tools WHERE source = 'code' AND deleted_at IS NULL
        AND name IN (#{PULL_REQUEST_TOOLS.map { |name| connection.quote(name) }.join(', ')})
    SQL
    return if tool_ids.empty?

    connections = select_rows(<<~SQL.squish)
      SELECT DISTINCT company_id, project_id FROM integrations
        WHERE provider IN (#{HOSTS.map { |host| connection.quote(host) }.join(', ')})
    SQL
    company_wide = connections.select { |_, project_id| project_id.nil? }.map { |company_id, _| company_id.to_i }
    companies = connections.map { |company_id, _| company_id.to_i }
    projects = connections.filter_map { |_, project_id| project_id&.to_i }

    MigrationWorkflow.where(deleted_at: nil).find_each do |workflow|
      reachable = company_wide.include?(workflow.company_id) ||
                  (workflow.project_id ? projects.include?(workflow.project_id) : companies.include?(workflow.company_id))
      next unless reachable

      config = workflow.config.to_h
      current = Array(config["base_tool_ids"])
      missing = tool_ids - current.map(&:to_i)
      next if missing.empty?

      workflow.update_columns(config: config.merge("base_tool_ids" => current + missing))
    end
  end

  def down
    # Irreversible by intent: after this runs, a pull-request tool in a workflow's base
    # list may have been attached by a person, and nothing records which.
  end
end
