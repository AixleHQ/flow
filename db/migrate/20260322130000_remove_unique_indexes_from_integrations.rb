# frozen_string_literal: true

class RemoveUniqueIndexesFromIntegrations < ActiveRecord::Migration[8.0]
  def change
    remove_index :integrations, name: "index_integrations_on_company_provider_when_company_wide", if_exists: true
    remove_index :integrations, name: "index_integrations_on_project_provider_when_scoped", if_exists: true

    add_index :integrations, %i[company_id provider],
              name: "index_integrations_on_company_id_and_provider",
              if_not_exists: true
    add_index :integrations, %i[project_id provider],
              name: "index_integrations_on_project_id_and_provider",
              where: "project_id IS NOT NULL",
              if_not_exists: true
  end
end
