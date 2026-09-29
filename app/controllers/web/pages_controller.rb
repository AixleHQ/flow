# frozen_string_literal: true

class Web::PagesController < Web::ApplicationController
  skip_before_action :enforce_onboarding
  skip_before_action :enforce_company_auth_policy

  def privacy_policy
    render layout: "web/legal"
  end

  def terms_of_service
    render layout: "web/legal"
  end
end
