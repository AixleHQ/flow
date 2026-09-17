# frozen_string_literal: true

# The sign-in link itself (CAP-4).
class MagicLinkMailer < ApplicationMailer
  def sign_in(user, token)
    @user = user
    # Built as a string, not through url_for: passing a `host` that carries a
    # port makes url_for split the two and then fall back to the environment's
    # default port, so the emailed link points somewhere the app is not. Invisible
    # in production, where the domain has no port — and broken everywhere else.
    @url = "#{Settings.protocol}://#{Settings.domain}#{magic_link_path(token: token)}"
    @ttl_minutes = (MagicLinkToken::TTL / 60).to_i

    mail(to: user.email, subject: "Your sign-in link")
  end
end
