# frozen_string_literal: true

module Trackers
  # Gives a platform connection that already names its external scopes — an
  # Azure DevOps connection names its Azure projects — a project tracker for each
  # of them, so connecting is enough to reach the boards. The first tracker of a
  # project becomes its primary.
  module Provisioning
    def self.ensure_for!(integration)
      return unless Trackers.provider?(integration.provider) && integration.project

      project = integration.project
      trackers = ProjectTracker.for_project(project)
      taken = trackers.pluck(:handle)
      has_primary = trackers.exists?(primary: true)

      Provider.for(integration).scopes.each do |scope|
        next if trackers.exists?(integration_id: integration.id, external_scope_id: scope.id)

        handle = ProjectTracker.handle_for(scope.name, taken: taken)
        taken << handle
        ProjectTracker.create!(project: project, integration: integration, external_scope_id: scope.id,
                               external_scope_key: scope.key, name: scope.name, handle: handle, primary: !has_primary)
        has_primary = true
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[Trackers::Provisioning] integration #{integration.id} scope #{scope.id}: #{e.message}")
      end
    end
  end
end
