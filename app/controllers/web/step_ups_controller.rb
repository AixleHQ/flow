# frozen_string_literal: true

# Step-up re-authentication (AD-5).
#
# A live session that does not satisfy the company it is entering lands here
# instead of being signed out. Proving one of that company's allowed methods
# appends a proof (AD-6) and returns the user to where they were going.
class Web::StepUpsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_company_auth_policy
  skip_before_action :enforce_onboarding
  before_action :require_signed_in

  def new
    company = target_company
    return redirect_to(company_projects_path) if company.nil? || company_auth_policy_satisfied?(company)

    render inertia: "Auth/StepUpPage", props: {
      company_name: company.branded_name,
      methods: allowed_methods(company),
      error: params[:error]
    }
  end

  def create
    company = target_company
    return redirect_to(company_projects_path) if company.nil?

    provider = IdentityProvider.deployment!(requested_kind)
    unless allowed_provider_ids(company).include?(provider.id)
      return redirect_to step_up_path(error: "method_not_allowed")
    end

    assertion = complete_with(provider)
    return redirect_to step_up_path(error: "invalid_credentials") if assertion.nil?

    prove_additional_method(provider)
    redirect_to company_projects_path
  end

  private

  # Only the two methods that can be completed by posting this form. A redirect
  # method has its own start path and never arrives here.
  def requested_kind
    kind = params.dig(:step_up, :kind).to_s
    %w[password totp].include?(kind) ? kind : "password"
  end

  def complete_with(provider)
    adapter = Auth::Registry.for(provider)

    if provider.totp?
      adapter.complete(user: current_user, code: params.dig(:step_up, :code).to_s)
    else
      adapter.complete(email: current_user.email, password: params.dig(:step_up, :password).to_s)
    end
  end

  def require_signed_in
    redirect_to login_path unless signed_in?
  end

  def target_company
    current_company
  end

  def allowed_provider_ids(company)
    Auth::PolicyResolver.allowed_provider_ids(company)
  end

  def allowed_methods(company)
    Auth::PolicyResolver.allowed_providers(company).map do |provider|
      {
        kind: provider.kind.to_s,
        name: provider.display_name,
        # Redirect methods need somewhere to POST to. Password is handled by the
        # form on this page and has no start path.
        start_path: start_path_for(provider)
      }
    end
  end

  def start_path_for(provider)
    case provider.kind.to_s
    when "oidc" then oidc_start_path(id: provider.id)
    when "google", "microsoft" then "/auth/#{provider.kind}"
    when "magic_link" then request_magic_link_path
    end
  end
end
