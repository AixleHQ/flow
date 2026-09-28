# frozen_string_literal: true

# Creating a company for yourself, which is the one path where the customer —
# not us — decides what the company is called and how much it may run.
#
# WHY A FORM AND NOT VALIDATIONS ON Company. Requiring a session limit is a rule
# of this path alone. Every other way a company comes into being — the admin, the
# seeds, the factories — legitimately makes one without a limit, and a model
# validation would refuse all of them to constrain one.
#
# The form is built twice for a stranger: once to check the answers before they
# are emailed, and again from the signed link to write them. Only the second
# call has anyone to own the company, which is why `save` takes the owner rather
# than holding one.
class WorkspaceOnboardingForm
  include ApplicationFormWithoutActiveRecord

  # A number is required here and nowhere else. Absence means unbounded and
  # unbilled, which is ours to grant from the admin — a company cannot arrive
  # that way by signing itself up.
  attribute :name, :string
  attribute :email, :string
  attribute :email_domain, :string
  attribute :max_sessions, :integer

  attr_reader :user, :company

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, message: "is not an email address" }
  validates :email_domain, presence: true
  validates :max_sessions, numericality: { only_integer: true, greater_than: 0 }
  validate :domain_is_free, if: -> { email_domain.present? }
  validate :domain_is_not_a_public_mailbox, if: -> { email_domain.present? }
  validate :domain_belongs_to_the_address, if: -> { email_domain.present? && email.present? }

  # `user:` is the person already signed in, whose address is not theirs to
  # choose. A stranger supplies one instead, and proves it by opening the link.
  def initialize(user: nil, **attributes)
    @user = user
    super(**attributes)
    self.email = user.email if user
    self.email = email.to_s.strip.downcase.presence
    self.email_domain = email_domain.to_s.strip.downcase.presence || email.to_s.split("@").last
  end

  def save(owner)
    return false unless valid?

    ActiveRecord::Base.transaction do
      @company = Company.create!(name: name.strip, email_domain: email_domain, state: "active")
      owner.save! if owner.new_record?
      owner.company_memberships.create!(company: @company, role: "admin", state: "active", accepted_at: Time.current)
      SessionConcurrencyLimit.set!(scope: @company, max_sessions: max_sessions)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    # Company's own validations — a reserved domain, a name already taken — and a
    # domain that was claimed between the check above and this write.
    e.record.errors.each { |error| errors.add(mapped_attribute(error.attribute), error.message) }
    false
  end

  # A person for the address, for the link's own writes. Not persisted here: the
  # transaction in `save` is what decides whether they exist at all, so a signup
  # that fails leaves no account behind.
  def owner_for(existing)
    existing || User.new(email: email, name: name_from_email, state: "active")
  end

  def name_from_email
    email.to_s.split("@").first.to_s.tr("._-", " ").split.map(&:capitalize).join(" ").presence || email.to_s
  end

  private

  def domain_is_free
    return unless Company.exists?(email_domain: email_domain)

    errors.add(:email_domain, "already has a workspace — ask someone there to invite you")
  end

  # Claiming a domain here takes it from everyone else at it, which is a bargain
  # only an organisation's own domain can keep. At a public mail service the
  # first person to sign up would take the service. Deliberately not a rule on
  # Company: an operator creating a workspace from the admin has reasons we do
  # not, and this is about what a stranger may claim unasked.
  def domain_is_not_a_public_mailbox
    return unless PublicEmailDomains.include?(email_domain)

    errors.add(
      :email_domain,
      "is a public email service — sign up with an address at your organisation's own domain"
    )
  end

  # Otherwise anyone could claim a domain they have no address at, and every
  # later sign-in from that domain would auto-join the workspace they built.
  def domain_belongs_to_the_address
    return if email_domain == email.to_s.split("@").last&.downcase

    errors.add(:email_domain, "must be the domain of your own email address")
  end

  def mapped_attribute(attribute)
    attribute == :base ? :base : attribute
  end
end
