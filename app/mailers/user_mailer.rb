# frozen_string_literal: true

class UserMailer < ApplicationMailer
  # Sent when a company admin invites a new team member.
  # The user's `state` is `pending`; they must set a password to activate.
  # Only called for users with an inviter (invited_by is set).
  def invite(user)
    @user    = user
    @inviter = user.invited_by
    @company = user.company

    mail(
      to:      user.email,
      subject: "You've been invited to #{@company.display_name} on Aixle Flow"
    )
  end
end
