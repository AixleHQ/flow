# frozen_string_literal: true

# One Insights connection per project: reconnecting replaces the token on the
# existing row (Insights::IntegrationService), and this index makes concurrent
# connects fail instead of stacking a second row.
class AddUniqueInsightsIntegrationPerProject < ActiveRecord::Migration[8.1]
  def change
    add_index :integrations, %i[project_id provider], unique: true,
              name: "index_integrations_on_project_insights",
              where: "provider = 'insights'",
              if_not_exists: true
  end
end
