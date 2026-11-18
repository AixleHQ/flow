# frozen_string_literal: true

# The admin's dashboard for a dashboard viewer (docs/design/tenant-usage-report.md
# §7.2): the same page and the same data, without the rest of the admin. A
# superadmin is sent to the admin's own copy, as from every other page here.
class Web::DashboardsController < Web::ApplicationController
  include DashboardViewerOnly
  include TenantDashboard

  layout "dashboard"

  helper_method :current_membership
end
