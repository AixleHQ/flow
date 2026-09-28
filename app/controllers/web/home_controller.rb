# frozen_string_literal: true

class Web::HomeController < Web::ApplicationController
  skip_before_action :enforce_onboarding
  skip_before_action :enforce_company_auth_policy

  # The landing page is hand-written marketing HTML driven by inline handlers
  # (onclick=…), and it shows no one's data. Inline script stays allowed here; a
  # nonce would switch 'unsafe-inline' off, so this page gets none.
  content_security_policy do |policy|
    policy.script_src(*policy.script_src, :unsafe_inline)
  end
  before_action { request.content_security_policy_nonce_directives = [] }

  def show
    if request.path == "/"
      render html: "", layout: "web/landing"
    elsif signed_in? && current_user.super_admin?
      redirect_to admin_users_path
    end
  end
end
