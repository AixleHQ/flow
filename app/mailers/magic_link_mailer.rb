# frozen_string_literal: true

# The sign-in link itself (CAP-4).
class MagicLinkMailer < ApplicationMailer
  def sign_in(user, token)
    @user = user
    @url = magic_link_url(token: token, host: Settings.domain, protocol: Settings.protocol)
    @ttl_minutes = (MagicLinkToken::TTL / 60).to_i

    mail(to: user.email, subject: "Your sign-in link")
  end
end
