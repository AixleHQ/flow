# frozen_string_literal: true

class UserSignInForm
  include ApplicationFormWithoutActiveRecord

  attribute :email, String
  attribute :password, String
  attribute :otp, String
  attribute :request_otp, Boolean

  validates :email, :password, presence: true
  validates :otp, presence: true, if: -> { !request_otp && Settings.authorization.otp_enabled }
  validate :check_valid_otp, if: -> { otp.present? && Settings.authorization.otp_enabled }
  validate :check_authenticate, if: :email

  def user
    @user ||= User.active.find_by(email: email)
  end

  def check_authenticate
    return unless wrong_email_or_password?

    errors.add(:email, :email_or_password_incorrect)
    errors.add(:password, :email_or_password_incorrect)
  end

  def check_valid_otp
    return if user.otp_verify(otp)

    errors.add(:otp, :invalid)
  end

  private

  def wrong_email_or_password?
    !user&.authenticate(password)
  end
end
