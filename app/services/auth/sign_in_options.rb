# frozen_string_literal: true

module Auth
  # What an address may be offered, decided by its DOMAIN alone.
  #
  # Never by whether an account exists. A screen that answers differently for a
  # known and an unknown address at the same domain is an oracle for which
  # addresses are registered — so this asks only which company claims the
  # domain, and what that company accepts.
  #
  # A domain no company claims gets the installation's own methods, not nil: a
  # member invited from another domain signs in from exactly such an address.
  class SignInOptions
    # Methods that can BEGIN a session. Authentication codes confirm a session
    # that already exists — there is nobody to look up from six digits — so they
    # are never offered here however the company's policy reads.
    STARTABLE_KINDS = %w[password passkey magic_link google microsoft].freeze

    attr_reader :company, :connections, :kinds

    def self.for(email)
      new(Company.find_by_email_domain(email.to_s))
    end

    def initialize(company)
      @company = company
      if company.nil?
        @connections = []
        @kinds = Auth::PolicyResolver.deployment_allowlist_kinds & STARTABLE_KINDS
        return
      end

      allowed = Auth::PolicyResolver.allowed_providers(company).to_a
      @connections = allowed.select { |provider| provider.company? && provider.oidc? }.sort_by(&:id)
      @kinds = allowed.select(&:deployment?).map { |provider| provider.kind.to_s } & STARTABLE_KINDS
    end

    def unclaimed? = company.nil?

    # A workspace with nothing left that can start a session. The stranding
    # guard on the policy screen is what should keep this empty, and saying so
    # plainly beats an empty step that looks broken.
    def dead_end?
      !unclaimed? && connections.empty? && kinds.empty?
    end
  end
end
