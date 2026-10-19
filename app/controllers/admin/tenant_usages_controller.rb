# frozen_string_literal: true

module Admin
  # The tenant report: what every company used, and whether it is billed for it
  # (docs/design/tenant-usage-report.md). An Administrate page with a React
  # island in it, fed the daily rows once.
  class TenantUsagesController < Admin::ApplicationController
    def show
      @report = Usage::TenantReport.new.to_h.deep_transform_keys { |key| key.to_s.camelize(:lower) }
      render layout: "administrate/application"
    end
  end
end
