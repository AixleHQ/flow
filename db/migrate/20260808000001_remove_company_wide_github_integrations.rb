# frozen_string_literal: true

# Company-wide GitHub integrations are legacy. Integrations kept Company scope
# when RestrictResourceScopesToProject (20260724000001) pushed everything else
# down to Project, but only because a Slack install genuinely serves the whole
# company (Slack::IntegrationService builds it with project_id: nil). GitHub has
# been connected per project since then — GithubSetupController treats a callback
# without a project as a misroute.
#
# The rows that predate that change are still visible on EVERY project's
# integrations page, because Integration.visible_for_project unions
# `project_id IS NULL` with the project's own rows, and they cannot be removed
# from the UI at all: IntegrationsController#destroy looks them up through
# `for_project`, which a company-wide row never matches.
#
# This migration DELETES those integrations and the repositories attached to
# them. The repositories go too: their clone credentials come from the
# installation being deleted, so leaving them behind would leave rows that look
# connected and fail on clone. Attached sessions lose their join rows through the
# session_repositories cascade; stale ids left in steps.repository_ids /
# workflows.config are resolved through a lookup and simply drop out.
#
# GitLab, Coder and Slack are untouched. The data deletion is irreversible.
class RemoveCompanyWideGithubIntegrations < ActiveRecord::Migration[8.0]
  def up
    # repositories -> integrations is RESTRICT, so the children go first.
    say_with_time "Removing repositories attached to company-wide GitHub integrations" do
      execute(<<~SQL.squish)
        DELETE FROM repositories
        WHERE integration_id IN (
          SELECT id FROM integrations WHERE project_id IS NULL AND provider = 'github'
        )
      SQL
    end

    # integration_data cascades at the DB.
    say_with_time "Removing company-wide GitHub integrations" do
      execute("DELETE FROM integrations WHERE project_id IS NULL AND provider = 'github'")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
