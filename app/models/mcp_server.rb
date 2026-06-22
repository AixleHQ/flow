# frozen_string_literal: true

# McpServer — MCP (Model Context Protocol) server configuration
#
# kind: internal | custom
# - internal: system-provided by Aixle (e.g., aixle-tools), no scope
# - custom: user-configured servers (Context7, Tavily, etc.) with Company/Project scope
#
# scope: Company | Project (polymorphic, null for internal)
class MCPServer < ApplicationRecord
  extend Enumerize

  enumerize :kind, in: %i[internal custom], default: :custom, predicates: true
  enumerize :transport, in: %i[http sse stdio], default: :http

  # Polymorphic scope (Company or Project, null for internal)
  belongs_to :scope, polymorphic: true, optional: true

  # Auto-downcase and sanitize name
  def name=(val)
    super(val&.downcase&.gsub(/[^a-z0-9_-]/, "-"))
  end

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[a-z][a-z0-9_-]*\z/, message: "must start with letter, use lowercase letters, numbers, dashes, underscores" }
  validates :name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :display_name, presence: true
  validates :kind, presence: true
  validates :url, presence: true, if: -> { custom? && !transport_stdio? }
  validates :command, presence: true, if: :transport_stdio?
  validates :scope, presence: true, if: :custom?
  validate :url_safety, if: -> { custom? && url.present? }

  # Scopes
  scope :internal_servers, -> { where(kind: "internal") }
  scope :custom_servers, -> { where(kind: "custom") }
  scope :for_company, ->(company) { custom_servers.where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { custom_servers.where(scope_type: "Project", scope_id: project.id) }
  scope :enabled, -> { where(enabled: true) }

  scope :visible_for_project, ->(project) {
    enabled.internal_servers
           .or(enabled.where(scope_type: "Company", scope_id: project.company_id))
           .or(enabled.where(scope_type: "Project", scope_id: project.id))
  }
  scope :visible_for_company, ->(company) {
    enabled.internal_servers
           .or(enabled.where(scope_type: "Company", scope_id: company.id))
  }

  def transport_stdio?
    transport.to_s == "stdio"
  end

  # Split "npx @playwright/mcp --headless" → ["npx", "@playwright/mcp", "--headless"]
  def parsed_command
    Shellwords.split(command.to_s)
  end

  def command_executable
    parsed_command.first
  end

  def command_args
    parsed_command.drop(1)
  end

  def picker_name
    display_name.presence || name
  end

  def scope_indicator
    return "internal" if internal?
    scope_type == "Company" ? "company" : "project"
  end

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[name display_name kind scope_type enabled created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end

  private

  def url_safety
    UrlSafetyValidator.errors_for(url).each { |msg| errors.add(:url, msg) }
  end
end
