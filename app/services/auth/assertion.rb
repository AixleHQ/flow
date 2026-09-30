# frozen_string_literal: true

module Auth
  # What an adapter returns. Controllers never see a provider-specific payload.
  #
  # `email_verified` is deliberately a plain boolean with no nil: an adapter that
  # cannot establish verification reports false. An absent claim is not a true
  # claim (AD-3).
  #
  # `email_domain_verified` is weaker: the issuing directory has proved it owns
  # the address's DOMAIN, so whoever holds the address is that domain owner's to
  # vouch for. That places someone in the company owning the same domain
  # (domain auto-join), but never adopts an existing account (promotion reads
  # email_verified only).
  Assertion = Struct.new(
    :provider, :subject, :email, :email_verified, :email_domain_verified, :name, :avatar_url,
    keyword_init: true
  ) do
    def email_verified?
      email_verified == true
    end

    def joinable_by_domain?
      email_verified? || email_domain_verified == true
    end

    def valid?
      provider.present? && subject.present?
    end
  end
end
