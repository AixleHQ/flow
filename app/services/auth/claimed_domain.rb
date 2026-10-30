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
      company && new(company, tried: tried, proved: true)
    end

    # For a typed address rather than a proved one, which is all an AWS
    # Marketplace buyer has: they are signed out on arrival. Answered narrowly
    # (#to_h), because a pay-as-you-go subscription costs nothing to take out.
    #
    # Any company, not only an active one: the form refuses the domain whatever
    # state its workspace is in (WorkspaceOnboardingForm#domain_is_free), so
    # scoping to active would refuse the buyer and then explain nothing.
    def self.for_email(email)
      return nil if email.blank?

      company = Company.find_by(email_domain: email.to_s.split("@").last)
      company && new(company, proved: false)
    end

    def initialize(company, tried: nil, proved: true)
      @company = company
      @tried = tried
      @proved = proved
    end

    # The workspace is named, and its ways in listed, only for an address its
    # owner has proved. Auto-join does not run for a typed one whatever the
    # method, so naming it would hand a stranger the workspace's name, sign-ins
    # and approval rule for any domain they care to type. The narrow answer
    # still says why the form refused: the domain is taken.
    def to_h
      return { domain: company.email_domain, workspace_name: nil, join_methods: [], approval_required: false } unless proved?

      {
        domain: company.email_domain,
        workspace_name: (company.branded_name if company.domain_verified?),
        join_methods: company.domain_verified? ? join_methods : [],
        approval_required: !company.auto_accept_users
      }
    end

    def proved? = @proved

    private

    # Nothing joins a workspace that is not running, so a suspended or archived
    # one is named with no way in rather than with one that would be refused.
    def join_methods
      return [] unless company.active?

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
