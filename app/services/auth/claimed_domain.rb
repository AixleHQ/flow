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

    # For somebody who has typed an address rather than proved one, which is the
    # only thing an AWS Marketplace buyer has: §5.1 signs them out on arrival,
    # because whoever pressed Subscribe in AWS is usually not whoever will use
    # the product. There is no user to check memberships against — not being
    # signed in is the whole of what is known — so this answers the narrower
    # question of whether the domain is taken.
    #
    # Only ever for a buyer, and answered narrowly even then -- see #to_h. A
    # subscription is what makes a visitor not arbitrary, but a pay-as-you-go
    # one costs nothing to take out, so it is a door and not a vouching: enough
    # to be told why the form refused, not enough to be read a workspace's name
    # and its ways in, one typed address at a time.
    #
    # Any company, not only an active one. `find_by_email_domain` is scoped to
    # active because its other caller is asking how to get in; this one is
    # asking why the form refused, and the form (WorkspaceOnboardingForm
    # #domain_is_free) refuses on every state. Scoped the same way, a domain
    # held by a suspended or archived workspace refused the buyer and then
    # explained nothing.
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
    # owner has proved. A typed one may be anybody's: auto-join does not run for
    # it whatever the method, so naming the workspace buys the person nothing
    # they can act on and hands a stranger its name, its sign-ins and whether
    # joining needs approval -- for any domain they care to type.
    #
    # The narrow answer still says the one thing the screen exists for: this
    # domain is taken, which is why the form refused.
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
