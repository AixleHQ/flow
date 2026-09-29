# frozen_string_literal: true

module Domains
  # Proving that a workspace owns the domain it claimed.
  #
  # Signing up proves a mailbox: that the person receives mail at an address. It
  # says nothing about the domain, and a workspace claims the whole of one —
  # everyone signing in from it joins, and nobody else may have it. A DNS record
  # is the part only the domain's owner can publish, so it is what the claim has
  # to rest on before anything is granted on the strength of it.
  module Verification
    # A record of its own rather than a value at the root: the root TXT set is
    # shared with SPF, DMARC and every other vendor's proof, and has a length
    # budget those already strain.
    HOST_PREFIX = "_aixle-challenge"
    RECORD_PREFIX = "aixle-domain-verification="

    module_function

    def token_for(company)
      company.domain_verification_token.presence || company.regenerate_domain_verification_token!
    end

    # Where the customer publishes it, and what they publish.
    def host_for(company)
      "#{HOST_PREFIX}.#{company.email_domain}"
    end

    def record_for(company)
      "#{RECORD_PREFIX}#{token_for(company)}"
    end

    # True once the record is there. Idempotent: a company already verified stays
    # verified without another lookup, so a screen that polls costs nothing.
    def verify!(company)
      return true if company.domain_verified?
      return false unless published?(company)

      company.update!(domain_verified_at: Time.current)
      true
    end

    def published?(company)
      expected = record_for(company)
      Dns::TxtLookup.call(host_for(company)).any? { |value| value.to_s.strip == expected }
    end
  end
end
