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

    # `provider:` is the method the person actually authenticated with. A
    # company that does not accept it must not gain a member through it: the
    # membership would be one the person can never enter (the entry gate refuses
    # it on every request), and — once active — it strands them permanently,
    # which makes Auth::PolicyUpdater refuse EVERY later policy edit by that
    # company's admins. A membership nobody can use is worse than no membership:
    # it reads as access, counts as a member, and quietly freezes the policy
    # screen.
    def call(user, email = user.email, provider:)
      return nil if user.super_admin?
      return nil if user.company_memberships.exists?

      company = Company.find_by_email_domain(email.to_s)
      return nil unless company
      return nil unless Auth::PolicyResolver.accepts?(company: company, provider: provider)

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
