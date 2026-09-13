# frozen_string_literal: true

# An Azure DevOps connection covers several projects, and a Service Hook
# subscription is created against ONE of them: `publisherInputs.projectId` is
# part of the subscription, not of the connection. With the old unique index on
# (integration, event_type) a connection could hold one subscription per event
# for the whole connection, so every project but the first would silently get no
# events — and its CI gates would fall back to the recovery sweep.
class ScopeAzureSubscriptionsToProject < ActiveRecord::Migration[8.1]
  def up
    add_column :azure_devops_subscriptions, :azure_project_id, :string

    # Rows that exist now belong to whichever single project their connection
    # was pinned to. Backfilled from the connection's own settings so the new
    # unique index has something distinct to work with; a row whose connection
    # lost its project is left null and re-created on the next provisioning.
    execute(<<~SQL.squish)
      UPDATE azure_devops_subscriptions s
      SET azure_project_id = COALESCE(
        i.settings ->> 'azure_project_id',
        i.settings -> 'azure_project_ids' ->> 0
      )
      FROM integrations i
      WHERE i.id = s.integration_id
    SQL

    remove_index :azure_devops_subscriptions, name: "idx_ado_subscriptions_integration_event"
    add_index :azure_devops_subscriptions, %i[integration_id azure_project_id event_type],
              unique: true, name: "idx_ado_subscriptions_integration_project_event"
  end

  def down
    remove_index :azure_devops_subscriptions, name: "idx_ado_subscriptions_integration_project_event"
    add_index :azure_devops_subscriptions, %i[integration_id event_type],
              unique: true, name: "idx_ado_subscriptions_integration_event"
    remove_column :azure_devops_subscriptions, :azure_project_id
  end
end
