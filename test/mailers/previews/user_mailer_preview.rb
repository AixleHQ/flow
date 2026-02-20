class UserMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:4000/rails/mailers/user_mailer/invite
  def invite
    user = User.all.sample || FactoryBot.build(:user, name: "John Doe", email: "john.doe@example.com")
    account = Account.all.sample || FactoryBot.build(:account, name: "Acme Corporation")

    # Create a temporary account_user with invitation token for preview
    account_user = AccountUser.new(
      user: user,
      account: account,
      invitation_token: "preview_token_123456789"
    )

    UserMailer.invite(account_user)
  end
end
