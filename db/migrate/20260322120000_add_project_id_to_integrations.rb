# frozen_string_literal: true

class AddProjectIdToIntegrations < ActiveRecord::Migration[8.0]
  def change
    add_reference :integrations, :project, foreign_key: true, null: true

    remove_index :integrations, %i[company_id provider], if_exists: true

    add_index :integrations, %i[company_id provider],
              unique: true,
              where: "project_id IS NULL",
              name: "index_integrations_on_company_provider_when_company_wide"

    add_index :integrations, %i[project_id provider],
              unique: true,
              where: "project_id IS NOT NULL",
              name: "index_integrations_on_project_provider_when_scoped"
  end
end
