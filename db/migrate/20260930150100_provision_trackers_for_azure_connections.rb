# frozen_string_literal: true

# Azure Boards work items moved from the azure_devops_*work_item* tools to the
# tracker_* tools, which act on project trackers. Every existing Azure
# connection gets one per Azure project it covers — what connecting does from
# now on (Trackers::Provisioning), inlined so the migration does not depend on
# application code that will change.
class ProvisionTrackersForAzureConnections < ActiveRecord::Migration[8.1]
  class MigrationIntegration < ActiveRecord::Base
    self.table_name = "integrations"
  end

  class MigrationProjectTracker < ActiveRecord::Base
    self.table_name = "project_trackers"
  end

  def up
    MigrationIntegration.where(provider: "azure_devops").where.not(project_id: nil).order(:id).find_each do |integration|
      settings = integration.settings.to_h
      names = project_names(settings)
      project_ids(settings).each do |scope_id|
        trackers = MigrationProjectTracker.where(project_id: integration.project_id)
        next if trackers.exists?(integration_id: integration.id, external_scope_id: scope_id)

        name = names[scope_id].presence || scope_id
        MigrationProjectTracker.create!(
          project_id: integration.project_id, integration_id: integration.id, provider: "azure_devops",
          external_scope_id: scope_id, name: name, handle: unique_handle(name, trackers.pluck(:handle)),
          primary: !trackers.exists?(primary: true), access: "read_write", status: "active", settings: {}
        )
      end
    end
  end

  def down
    MigrationProjectTracker.where(provider: "azure_devops").delete_all
  end

  private

  def project_ids(settings)
    ids = Array(settings["azure_project_ids"]).map(&:to_s).compact_blank
    ids.presence || Array(settings["azure_project_id"]).map(&:to_s).compact_blank
  end

  def project_names(settings)
    stored = settings["azure_project_names"]
    return stored.to_h { |k, v| [ k.to_s, v.to_s ] } if stored.is_a?(Hash) && stored.present?
    return {} if settings["azure_project_id"].blank?

    { settings["azure_project_id"].to_s => settings["azure_project_name"].to_s }
  end

  def unique_handle(name, taken)
    base = name.to_s.parameterize.first(60).delete_suffix("-").presence || "tracker"
    candidate = base
    suffix = 1
    candidate = "#{base}-#{suffix += 1}" while taken.include?(candidate)
    candidate
  end
end
