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

    # For somebody who has typed an address rather than proved one, which is the
    # only thing an AWS Marketplace buyer has: §5.1 signs them out on arrival,
    # because whoever pressed Subscribe in AWS is usually not whoever will use
    # the product. There is no user to check memberships against — not being
    # signed in is the whole of what is known — so this answers the narrower
    # question of whether the domain is taken.
    #
    # Only ever for a buyer. Telling an arbitrary visitor whether a domain has a
    # workspace, and what it is called, is not ours to give away on a typed
    # address; a paid subscription is what makes them not arbitrary.
    # Any company, not only an active one. `find_by_email_domain` is scoped to
    # active because its other caller is asking how to get in; this one is
    # asking why the form refused, and the form (WorkspaceOnboardingForm
    # #domain_is_free) refuses on every state. Scoped the same way, a domain
    # held by a suspended or archived workspace refused the buyer and then
    # explained nothing.
    def self.for_email(email)
      return nil if email.blank?

      company = Company.find_by(email_domain: email.to_s.split("@").last)
      company && new(company)
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
