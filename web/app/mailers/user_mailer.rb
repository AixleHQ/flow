class UserMailer < ApplicationMailer
  def invite(account_user)
    @user = account_user.user
    @account = account_user.account
    @invitation_url = confirm_api_v1_users_url(invitation_token: account_user.invitation_token)

    mail(
      to: @user.email,
      subject: t(".subject", account_name: @account.name)
    )
  end

  def otp(user)
    @user = user
    @otp = user.otp_generate

    mail(
      to: @user.email,
      subject: t(".subject")
    )
  end
end
