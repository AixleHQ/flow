# frozen_string_literal: true

module Auth
  # Someone who belongs to no workspace, at a domain that already has one. They
  # cannot start a second workspace for it (WorkspaceOnboardingForm#domain_is_free),
  # so what they need is the way into the one that exists: a sign-in that joins
  # it, or an invitation.
  class ClaimedDomain
    # Only these sign-ins run domain auto-join. A password, a passkey or an
    # emailed link admits someone who is already a member and adds nobody, so
    # naming one here would send the person straight back to this screen.
    JOINING_KINDS = %w[google microsoft].freeze

    attr_reader :company

    # `tried:` is the method the person has just signed in with. Whatever kept
    # them out through it (an address it did not prove) keeps them out the next
    # time too.
    def self.for(user, tried: nil)
      return nil if user.super_admin? || user.company_memberships.exists?

      company = Company.find_by_email_domain(user.email.to_s)
      company && new(company, tried: tried)
    end

    def initialize(company, tried: nil)
      @company = company
      @tried = tried
    end

    # The workspace is named, and its ways in listed, only for a proved domain.
    # An unproved claim may be somebody else's, and auto-join does not run for it
    # whatever the method, so an invitation is the only way in.
    def to_h
      {
        domain: company.email_domain,
        workspace_name: (company.branded_name if company.domain_verified?),
        join_methods: company.domain_verified? ? join_methods : [],
        approval_required: !company.auto_accept_users
      }
    end

    private

    def join_methods
      Auth::PolicyResolver.allowed_providers(company)
                          .select { |provider| joins?(provider) && provider != @tried }
                          .sort_by { |provider| [ provider.company? ? 1 : 0, provider.display_name ] }
                          .map(&:display_name)
    end

    def joins?(provider)
      provider.company? ? provider.oidc? : JOINING_KINDS.include?(provider.kind.to_s)
    end
  end
end
