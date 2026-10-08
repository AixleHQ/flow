# frozen_string_literal: true

class Company < ApplicationRecord
  # State machine
  include CompanyStateMachine

  # Shrine attachment
  include LogoUploader::Attachment(:logo)

  # Associations
  has_many :company_memberships, dependent: :destroy
  # Only ACTIVE members: revoked/invited/suspended users must not leak into
  # consumers (member pickers, session scopes). Screens that need non-active
  # rows (e.g. the members index) go through :company_memberships directly.
  has_many :users, -> { merge(CompanyMembership.active).not_deleted }, through: :company_memberships
  has_many :projects, dependent: :destroy
  has_many :config_items, as: :scope, dependent: :destroy
  has_many :agents, as: :scope, dependent: :destroy
  has_many :tools, as: :scope, dependent: :destroy
  has_many :mcp_servers, as: :scope, dependent: :destroy, class_name: "MCPServer"
  has_many :skills, as: :scope, dependent: :destroy
  has_many :assets, as: :scope, dependent: :destroy
  has_many :folders, as: :scope, dependent: :destroy
  has_many :integrations, dependent: :destroy
  has_many :oauth_credentials, as: :owner, dependent: :destroy
  # After :integrations — an installation refuses to go while integrations use it.
  has_many :azure_devops_installations, dependent: :destroy
  # Auth policy rows and this company's own IdP connections die with it.
  has_many :company_auth_policies, dependent: :destroy
  has_many :identity_providers, dependent: :destroy
  has_many :repositories, as: :scope, dependent: :destroy
  # Workflows are owned by projects (company-level workflows were removed).
  # A company's workflows are the aggregate of its projects' workflows.
  # Cascade on destroy is handled by projects' own `dependent: :destroy`.
  has_many :workflows, through: :projects
  # Every session records the company it acts for (project-less logins
  # included). After :projects, whose destroy detaches their sessions.
  has_many :terminal_sessions, dependent: :destroy
  has_many :agent_credentials, dependent: :destroy
  has_many :trigger_events, dependent: :destroy
  has_many :billing_cancellations, dependent: :delete_all

  # A session whose runtime is still being torn down holds a reservation, and
  # destroying it would free a slot that is not free (TerminalSession refuses).
  # Refused up front, with a reason, instead of failing halfway on a foreign key.
  before_destroy :refuse_while_runtimes_remain, prepend: true

  # Virtual attributes for initial admin creation (used in admin form)
  attr_accessor :initial_admin_email, :initial_admin_password

  # Where we host, a company that signs itself up runs on a free allowance of
  # capacity before anyone has paid for anything (Billing::Trial).
  #
  #   trialing  spending the allowance, capped to one session at a time,
  #             invoiced for nothing
  #   active    someone is paying; the company's own limit is the only bound
  #   blocked   runs nothing, for the reason in `billing_block_reason`
  #
  # Meaningless outside the hosted product: a self-hosted operator pays nobody
  # and a Marketplace customer already bought their capacity from AWS. Every
  # company that existed before this shipped is `active`.
  BILLING_STATES = %w[trialing active blocked].freeze

  # Each one is undone differently, which is why it is kept: a spent allowance and
  # an ended subscription both need a new card through Checkout, while a failed
  # payment needs its open invoice paid — a second subscription would bill the
  # same metered minutes twice.
  BILLING_BLOCK_REASONS = %w[allowance canceled payment_failed].freeze

  # What a company we carry (`managed_by_aixle`) is given when it is made. Its
  # admins cannot change it; we can, from the admin.
  MANAGED_SESSION_LIMIT = 2

  # Constants
  RESERVED_DOMAINS = %w[
    admin.com api.com www.com app.com mail.com ftp.com
    assets.com cdn.com secure.com docs.com help.com
    support.com blog.com status.com localhost.com
  ].freeze

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validates :billing_state, inclusion: { in: BILLING_STATES }
  validates :billing_block_reason, inclusion: { in: BILLING_BLOCK_REASONS }, allow_nil: true
  validates :email_domain, presence: true, uniqueness: { case_sensitive: false },
                           format: { with: /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/, message: "must be a valid domain (e.g., acme.com, aixle.com)" }
  validate :email_domain_not_reserved
  validate :session_concurrency_limit_is_a_positive_integer

  # Callbacks
  before_validation :generate_slug, on: :create
  # An absent policy row means denied (AD-4), so every company gets an explicit,
  # enabled row per deployment provider the moment it exists.
  after_create :seed_auth_policies
  before_validation :downcase_email_domain
  # Before forget_billing_block, so a blocked company that becomes ours loses
  # its block reason with its block.
  before_validation :keep_managed_company_running, if: :managed_by_aixle?
  before_validation :forget_billing_block, unless: :billing_blocked?
  after_save :apply_session_concurrency_limit

  scope :billing_billable, -> { where(billing_state: "active", managed_by_aixle: false) }

  def billing_trialing? = billing_state == "trialing"
  def billing_active? = billing_state == "active"
  def billing_blocked? = billing_state == "blocked"

  def billing_cancellation_scheduled? = billing_active? && billing_cancels_at.present?

  # The one word the billing screen and the banner are written against.
  def billing_status
    case billing_state
    when "trialing" then "trialing"
    when "active" then billing_cancellation_scheduled? ? "cancelling" : "active"
    else billing_block_reason.presence || "allowance"
    end
  end

  def billing_admins
    users.where(company_memberships: { role: "admin" })
  end

  scope :domain_verified, -> { where.not(domain_verified_at: nil) }

  # A claimed domain and a proved one are different things. Claiming happens at
  # signup and proves a mailbox; proving happens in DNS, and it is what auto-join
  # rests on.
  def domain_verified? = domain_verified_at.present?

  def regenerate_domain_verification_token!
    update_column(:domain_verification_token, SecureRandom.hex(16))
    domain_verification_token
  end

  # Backed by a SessionConcurrencyLimit row, not a column, so the drain reads
  # both tiers from one table. Nil means unbounded and unbilled.
  def session_concurrency_limit
    return @session_concurrency_limit if defined?(@session_concurrency_limit)

    SessionConcurrencyLimit.for_company(id)
  end

  def session_concurrency_limit=(value)
    @session_concurrency_limit = value.to_s.strip.presence
    @session_concurrency_limit_assigned = true
  end

  def refuse_while_runtimes_remain
    return unless SessionAdmission.unreleased.joins(:terminal_session).where(terminal_sessions: { company_id: id }).exists?

    errors.add(:base, "This company still has sessions whose runtime is being cleaned up; stop them and try again")
    throw :abort
  end

  # White label / branding helpers
  def branded_name
    display_name.presence || name
  end

  def logo_url
    logo&.url
  end

  def branding
    {
      name: branded_name,
      email_domain: email_domain,
      logo_url: logo_url,
      primary_color: primary_color || "#4785FF",
      secondary_color: secondary_color || "#bb9af7"
    }
  end

  def self.find_by_email_domain(email)
    domain = email.split("@").last # e.g., "acme.com", "aixle.com"
    active.find_by(email_domain: domain)
  end


  # A viewer is read-only and must never own a project, so only employees and
  # admins qualify.
  def ownership_candidates
    users.where(company_memberships: { role: %w[employee admin] })
  end

  private

  # Nobody pays for a company we carry, so it has no allowance to spend and no
  # subscription to lapse: neither trialing nor blocked means anything for it.
  def keep_managed_company_running
    self.billing_state = "active"
  end

  # A company that is running again has no reason to be stopped, and an unpaid
  # invoice it was pointed at belongs to the stop that has just been undone.
  def forget_billing_block
    self.billing_block_reason = nil
    self.billing_unpaid_invoice_url = nil
  end

  # Only when the form submitted the field, so saving a logo cannot silently
  # exempt a customer from billing.
  def apply_session_concurrency_limit
    return unless @session_concurrency_limit_assigned

    @session_concurrency_limit_assigned = false
    row = SessionConcurrencyLimit.find_by(scope_type: "Company", scope_id: id)

    if @session_concurrency_limit.blank?
      row&.destroy
    else
      record = row || SessionConcurrencyLimit.new(scope_type: "Company", scope_id: id)
      record.update!(max_sessions: @session_concurrency_limit)
    end
  end

  # Here rather than on the row, so the admin form reports it instead of the
  # after_save callback raising.
  def session_concurrency_limit_is_a_positive_integer
    return unless @session_concurrency_limit_assigned

    if @session_concurrency_limit.blank?
      return unless Deployment.requires_bounded_companies?

      return errors.add(:session_concurrency_limit,
                        "is required: this installation meters its capacity to AWS Marketplace, " \
                        "where unlimited cannot be expressed")
    end

    return if @session_concurrency_limit.match?(/\A[1-9]\d*\z/)

    errors.add(:session_concurrency_limit, "must be a positive whole number, or blank for no limit")
  end

  def seed_auth_policies
    Auth::CompanyPolicySeeder.seed!(self)
  end

  def generate_slug
    return if slug.present?

    base_slug = name.to_s.parameterize
    self.slug = base_slug

    # Ensure uniqueness
    counter = 1
    while Company.exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def downcase_email_domain
    email_domain&.downcase!
  end

  def email_domain_not_reserved
    errors.add(:email_domain, "is reserved") if email_domain.present? && RESERVED_DOMAINS.include?(email_domain)
  end
end
