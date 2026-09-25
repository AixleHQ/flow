# frozen_string_literal: true

# Signing up a company for yourself. Only where we host and invoice: a
# self-hosted operator creates companies from the admin, and a Marketplace
# installation belongs to the customer who bought it — in neither does a stranger
# who signed in get to conjure a workspace.
class Web::WorkspacesController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_onboarding
  skip_before_action :enforce_workspace
  before_action :require_auth
  before_action :require_self_serve_signup
  before_action :require_no_membership

  def new
    render inertia: "Workspaces/NewPage", props: props(form)
  end

  def create
    built = WorkspaceOnboardingForm.new(user: current_user, **workspace_params.to_h.symbolize_keys)

    if built.save
      redirect_to onboarding_path, notice: "#{built.company.name} is ready"
    else
      redirect_to new_workspace_path, inertia: { errors: built.errors.to_hash(true) }
    end
  end

  private

  def form
    WorkspaceOnboardingForm.new(user: current_user)
  end

  def props(form)
    {
      suggested_domain: form.email_domain,
      suggested_name: form.email_domain.to_s.split(".").first&.capitalize,
      default_max_sessions: SessionAdmissionPolicy.scope_default("Project")
    }
  end

  def workspace_params
    params.fetch(:workspace, {}).permit(:name, :email_domain, :max_sessions)
  end

  def require_auth
    redirect_to login_path unless signed_in?
  end

  def require_self_serve_signup
    redirect_to login_path(error: "no_workspace") unless Deployment.saas?
  end

  # Someone who already belongs somewhere has no business here, and a super admin
  # belongs nowhere on purpose.
  def require_no_membership
    return if current_user && !current_user.super_admin? && !current_user.company_memberships.exists?

    redirect_to root_path
  end
end
