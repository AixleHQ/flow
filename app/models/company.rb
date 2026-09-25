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
  has_many :repositories, as: :scope, dependent: :destroy
  # Workflows are owned by projects (company-level workflows were removed).
  # A company's workflows are the aggregate of its projects' workflows.
  # Cascade on destroy is handled by projects' own `dependent: :destroy`.
  has_many :workflows, through: :projects
  # Sessions belong to the company through its PROJECTS (not through users —
  # a multi-company user's sessions in another company must never leak in).
  has_many :terminal_sessions, through: :projects

  # Virtual attributes for initial admin creation (used in admin form)
  attr_accessor :initial_admin_email, :initial_admin_password

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
  validates :email_domain, presence: true, uniqueness: { case_sensitive: false },
                           format: { with: /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/, message: "must be a valid domain (e.g., acme.com, aixle.com)" }
  validate :email_domain_not_reserved
  validate :session_concurrency_limit_is_a_positive_integer

  # Callbacks
  before_validation :generate_slug, on: :create
  before_validation :downcase_email_domain
  after_save :apply_session_concurrency_limit

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

  private

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
