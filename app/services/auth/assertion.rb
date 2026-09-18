# frozen_string_literal: true

module Auth
  # What an adapter returns. Controllers never see a provider-specific payload.
  #
  # `email_verified` is deliberately a plain boolean with no nil: an adapter that
  # cannot establish verification reports false. An absent claim is not a true
  # claim (AD-3).
  Assertion = Struct.new(
    :provider, :subject, :email, :email_verified, :name, :avatar_url,
    keyword_init: true
  ) do
    def email_verified?
      email_verified == true
    end

    def valid?
      provider.present? && subject.present?
    end
  end
end
