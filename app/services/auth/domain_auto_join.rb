# frozen_string_literal: true

module Auth
  # Email-domain match is an AUTO-JOIN policy, not a membership requirement: it
  # applies only to users with ZERO memberships (any state), so an existing or
  # pending invitation always wins over it. `auto_accept_users` decides whether
  # the auto-joined membership is active immediately or awaits admin approval.
  #
  # Lifted verbatim out of the old GoogleOmniAuthService (now deleted) so every
  # provider that can create a user reaches the same policy, not just Google.
  module DomainAutoJoin
    module_function

    def call(user, email = user.email)
      return nil if user.super_admin?
      return nil if user.company_memberships.exists?

      company = Company.find_by_email_domain(email.to_s)
      return nil unless company

      if company.auto_accept_users
        user.company_memberships.create!(
          company: company, role: "employee", state: "active", accepted_at: Time.current
        )
      else
        user.company_memberships.create!(company: company, role: "employee", state: "invited")
      end
    end
  end
end
