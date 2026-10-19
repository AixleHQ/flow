# frozen_string_literal: true

module Admin
  # The admin home: the platform at a glance and what every company used, with
  # whether it is billed for it (docs/design/tenant-usage-report.md). An
  # Administrate page with a React island in it, fed its data once.
  class DashboardsController < Admin::ApplicationController
    def show
      @report = Usage::TenantReport.new.to_h.deep_transform_keys { |key| key.to_s.camelize(:lower) }
      render layout: "administrate/application"
    end
  end
end
