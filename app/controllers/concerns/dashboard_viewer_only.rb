# frozen_string_literal: true

# The platform dashboard outside the admin (docs/design/tenant-usage-report.md
# §7.2), for whoever a superadmin marked a dashboard viewer. It is no company's
# data, so a company's gates — its sign-in policy, its terms, its onboarding —
# do not stand in front of it.
module DashboardViewerOnly
  extend ActiveSupport::Concern

  included do
    skip_before_action :enforce_workspace, :enforce_company_auth_policy, :enforce_legal_acceptance,
                       :enforce_onboarding
    before_action :require_dashboard_viewer
  end

  private

  # Anyone else is told there is nothing here, not that it is closed to them.
  def require_dashboard_viewer
    return redirect_to(login_path) unless signed_in?

    render_not_found unless current_user.dashboard_viewer?
  end
end
