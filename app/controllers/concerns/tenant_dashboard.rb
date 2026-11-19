# frozen_string_literal: true

# The dashboard's page (docs/design/tenant-usage-report.md), fed its report once.
# Shown in the admin to a superadmin and at /dashboard to a dashboard viewer
# (§7.2); each controller guards its own and wraps it in its own layout.
module TenantDashboard
  extend ActiveSupport::Concern

  def show
    @report = Usage::TenantReport.new.to_h.deep_transform_keys { |key| key.to_s.camelize(:lower) }
  end
end
