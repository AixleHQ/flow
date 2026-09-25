# frozen_string_literal: true

# Creating a company for yourself, which is the one path where the customer —
# not us — decides what the company is called and how much it may run.
#
# WHY A FORM AND NOT VALIDATIONS ON Company. Requiring a session limit is a rule
# of this path alone. Every other way a company comes into being — the admin, the
# seeds, the factories — legitimately makes one without a limit, and a model
# validation would refuse all of them to constrain one.
class WorkspaceOnboardingForm
  include ApplicationFormWithoutActiveRecord

  # A number is required here and nowhere else. Absence means unbounded and
  # unbilled, which is ours to grant from the admin — a company cannot arrive
  # that way by signing itself up.
  attribute :name, :string
  attribute :email_domain, :string
  attribute :max_sessions, :integer

  attr_reader :user, :company

  validates :name, presence: true, length: { maximum: 100 }
  validates :email_domain, presence: true
  validates :max_sessions, numericality: { only_integer: true, greater_than: 0 }
  validate :domain_is_free, if: -> { email_domain.present? }
  validate :domain_is_the_one_they_signed_in_with, if: -> { email_domain.present? && user }

  def initialize(user:, **attributes)
    @user = user
    super(**attributes)
    self.email_domain = email_domain.to_s.strip.downcase.presence || user&.email.to_s.split("@").last
  end

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      @company = Company.create!(name: name.strip, email_domain: email_domain, state: "active")
      user.company_memberships.create!(company: @company, role: "admin", state: "active", accepted_at: Time.current)
      SessionConcurrencyLimit.set!(scope: @company, max_sessions: max_sessions)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    # Company's own validations — a reserved domain, a name already taken — and a
    # domain that was claimed between the check above and this write.
    e.record.errors.each { |error| errors.add(mapped_attribute(error.attribute), error.message) }
    false
  end

  private

  def domain_is_free
    return unless Company.exists?(email_domain: email_domain)

    errors.add(:email_domain, "already has a workspace — ask someone there to invite you")
  end

  # Otherwise anyone could claim a domain they have no address at, and every
  # later sign-in from that domain would auto-join the workspace they built.
  def domain_is_the_one_they_signed_in_with
    return if email_domain == user.email.to_s.split("@").last&.downcase

    errors.add(:email_domain, "must be the domain of your own email address")
  end

  def mapped_attribute(attribute)
    attribute == :base ? :base : attribute
  end
end
