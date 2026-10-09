# frozen_string_literal: true

# A forgotten password's reset link, and the notice that follows every change
# to a password — the one sign of a takeover its owner is sure to see.
class PasswordMailer < ApplicationMailer
  SUBJECTS = {
    "set" => "A password was set on your Aixle Flow account",
    "changed" => "Your Aixle Flow password was changed",
    "reset" => "Your Aixle Flow password was reset"
  }.freeze
  SUMMARIES = {
    "set" => "A password was set on your Aixle Flow account. You can now sign in with your email address and that password.",
    "changed" => "The password for your Aixle Flow account was changed.",
    "reset" => "The password for your Aixle Flow account was reset through an emailed link."
  }.freeze

  # The token is minted here, at delivery, rather than by the caller: it is
  # signed over the current password, so a link made before a change would
  # arrive already spent.
  def reset(user)
    @user = user
    @url = edit_password_reset_url(token: user.password_reset_token)
    @ttl_minutes = (user.password_reset_token_expires_in / 60).to_i

    mail(to: user.email, subject: "Reset your Aixle Flow password")
  end

  # @param event [String] "set", "changed" or "reset"
  def updated(user, event)
    @user = user
    @summary = SUMMARIES.fetch(event)
    @reset_url = new_password_reset_url(email: user.email)

    mail(to: user.email, subject: SUBJECTS.fetch(event))
  end
end
