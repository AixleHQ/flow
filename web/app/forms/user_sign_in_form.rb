# frozen_string_literal: true

class UserSignInForm
  include ApplicationFormWithoutActiveRecord

  attribute :email, String
  attribute :password, String

  validates :email, :password, presence: true
  validate :check_authenticate, if: :email

  def user
    @user ||= User.with_state(:active).find_by(email: email)
  end

  def check_authenticate
    return unless wrong_email_or_password?

    errors.add(:email, :email_or_password_incorrect)
    errors.add(:password, :email_or_password_incorrect)
  end

  private

  def wrong_email_or_password?
    !user&.authenticate(password)
  end
end
