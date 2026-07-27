# frozen_string_literal: true

class UserSignInForm
  include ApplicationFormWithoutActiveRecord

  attribute :email, :string
  attribute :password, :string

  validates :email, :password, presence: true
  validate :check_authenticate, if: :email

  # `active` is the AASM account-state scope; `not_deleted` additionally excludes
  # soft-deleted accounts, matching AuthConcern#current_user. Without it a
  # deleted user authenticates successfully, gets a session, and then bounces in
  # a redirect loop because current_user resolves to nil.
  def user
    @user ||= User.active.not_deleted.find_by(email: email)
  end

  def check_authenticate
    return unless wrong_email_or_password?

    errors.add(:email, :email_or_password_incorrect)
    errors.add(:password, :email_or_password_incorrect)
  end

  private

  def wrong_email_or_password?
    if user
      !user.authenticate(password)
    else
      # Run a dummy bcrypt comparison to equalize response timing regardless of
      # whether the email exists, preventing user enumeration via timing.
      BCrypt::Password.new("$2a$12$R9h/cIPz0gi.URNNX3kh2OPST9/PgBkqquzi.Ss7KIUgO2t0jWMUW") == password
      true
    end
  end
end
