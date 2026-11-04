# frozen_string_literal: true

# A signed-in person's answer to the analytics banner, or their later change of
# mind from Profile → Privacy. Stored on the account, so it holds on every device.
class Web::AnalyticsConsentsController < Web::ApplicationController
  # A person's own preference, answerable before they belong to a company or
  # have finished entering one.
  skip_before_action :enforce_workspace
  skip_before_action :enforce_company_auth_policy
  skip_before_action :enforce_onboarding
  skip_before_action :enforce_legal_acceptance
  before_action :require_auth

  def update
    # Consent is the person's own to give: an operator acting as them may not.
    return head(:forbidden) if impersonated?

    choice = params[:consent].to_s
    return head(:unprocessable_content) unless User::ANALYTICS_CONSENTS.include?(choice)

    current_user.record_analytics_consent!(choice)
    redirect_back_or_to(privacy_profile_path, status: :see_other)
  end

  private

  def require_auth
    head(:unauthorized) unless signed_in?
  end
end
