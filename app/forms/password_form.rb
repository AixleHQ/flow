# frozen_string_literal: true

# A password the person chooses for themselves: set or changed from Profile →
# Security, or chosen through an emailed reset link.
#
# The current password is asked for only when there is one and the person did
# not arrive through a reset link: someone setting a first password has nothing
# to retype, and someone who forgot theirs cannot.
class PasswordForm
  include ApplicationFormWithoutActiveRecord

  AUDIT_VERBS = {
    "set" => "set a password",
    "changed" => "changed their password",
    "reset" => "reset their password through an emailed link"
  }.freeze

  attribute :current_password, :string
  attribute :password, :string
  attribute :password_confirmation, :string

  validate :current_password_matches, if: :current_password_required?
  validate :password_acceptable
  validate :password_confirmed

  attr_reader :user, :event

  def initialize(user:, reset_token: nil, **attributes)
    @user = user
    @reset_token = reset_token
    super(**attributes)
  end

  def current_password_required?
    !reset? && user.password_set?
  end

  # Checked and written under a lock on the user, so a reset link submitted
  # twice at once is spent by the first submission and refused to the second.
  def save(request:)
    saved = user.with_lock do
      next false unless valid? && reset_link_live?

      @event = event_for_this_write
      user.update(password: password) || copy_user_errors
    end
    return false unless saved

    PasswordMailer.updated(user, event).deliver_later
    Audit.create!(auditable: user, user: user, action: "password_#{event}", comment: "#{user.email} #{AUDIT_VERBS.fetch(event)}",
                  audited_changes: {}, remote_address: request.remote_ip, request_uuid: request.uuid)
    true
  end

  # One message per field, which is what the form shows under each input.
  def error_messages
    errors.to_hash.transform_values(&:first)
  end

  private

  def reset?
    !@reset_token.nil?
  end

  def event_for_this_write
    return "reset" if reset?

    user.password_set? ? "changed" : "set"
  end

  def reset_link_live?
    return true unless reset?
    return true if User.find_by_password_reset_token(@reset_token) == user

    errors.add(:base, "This link has already been used or has expired.")
    false
  end

  def current_password_matches
    if current_password.blank?
      errors.add(:current_password, "Enter your current password.")
    elsif !user.authenticate(current_password)
      errors.add(:current_password, "That is not your current password.")
    end
  end

  # bcrypt reads only the first 72 bytes; anything past them would be ignored
  # without a word, so a longer password is refused rather than truncated.
  def password_acceptable
    if password.blank?
      errors.add(:password, "Enter a new password.")
    elsif password.length < User::PASSWORD_MIN_LENGTH
      errors.add(:password, "Use at least #{User::PASSWORD_MIN_LENGTH} characters.")
    elsif password.bytesize > ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED
      errors.add(:password, "Use at most #{ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED} bytes.")
    end
  end

  def password_confirmed
    return if password.blank? || password == password_confirmation

    errors.add(:password_confirmation, "The passwords do not match.")
  end

  def copy_user_errors
    user.errors.each { |error| errors.add(error.attribute, error.message) }
    false
  end
end
