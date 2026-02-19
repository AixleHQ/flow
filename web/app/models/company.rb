# frozen_string_literal: true

class Company < ApplicationRecord
  # State machine
  include CompanyStateMachine

  # Shrine attachment
  include LogoUploader::Attachment(:logo)

  # Associations
  has_many :users, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :config_items, as: :scope, dependent: :destroy
  has_many :agents, as: :scope, dependent: :destroy
  has_many :tools, as: :scope, dependent: :destroy
  has_many :mcp_servers, as: :scope, dependent: :destroy, class_name: "MCPServer"
  has_many :skills, as: :scope, dependent: :destroy
  has_many :assets, as: :scope, dependent: :destroy
  has_many :integrations, dependent: :destroy
  has_many :terminal_sessions, through: :users

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
                           format: { with: /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/, message: "must be a valid domain (e.g., acme.com, palad.ai)" }
  validate :email_domain_not_reserved

  # Callbacks
  before_validation :generate_slug, on: :create
  before_validation :downcase_email_domain

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
    domain = email.split("@").last # e.g., "acme.com", "palad.ai"
    active.find_by(email_domain: domain)
  end

  private

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
