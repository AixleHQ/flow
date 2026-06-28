# frozen_string_literal: true

# A Slack workspace install belongs to a COMPANY and serves all its projects
# (events fan out by channel). Detach existing Slack installs from a single
# project so the same workspace can drive multiple projects. Idempotent.
class ScopeSlackInstallsToCompany < ActiveRecord::Migration[8.0]
  class MigEndpoint < ActiveRecord::Base
    self.table_name = "webhook_endpoints"
  end

  class MigIntegration < ActiveRecord::Base
    self.table_name = "integrations"
  end

  def up
    MigEndpoint.where(provider: "slack").where.not(project_id: nil).update_all(project_id: nil)
    MigIntegration.where(provider: "slack").where.not(project_id: nil).update_all(project_id: nil)
  end

  def down
    # Original project bindings are not recoverable; no-op.
  end
end
