# frozen_string_literal: true

# McpServer — MCP (Model Context Protocol) server configuration
#
# kind: internal | custom | managed
# - internal: system-provided by Aixle (e.g., aixle-tools), no scope
# - custom:   user-configured servers (Context7, Tavily, etc.) with Company/Project scope
# - managed:  auto-provisioned by an integration (e.g., Coder); 1:1 with `integration_id`.
#             Lifecycle bound to the integration via FK cascade. The MCP tools surfaced
#             through a managed server are dispatched in-process by `execution_mode: :app`,
#             so the `url` / `transport` columns are cosmetic for managed rows.
#
# scope: Company | Project (polymorphic, null for internal; inherited from integration for managed)
class MCPServer < ApplicationRecord
  extend Enumerize

  enumerize :kind, in: %i[internal custom managed], default: :custom, predicates: true
  enumerize :transport, in: %i[http sse stdio], default: :http
  enumerize :auth_type, in: %i[none static oauth],
                        default: :none, predicates: { prefix: true }, scope: true
  enumerize :credential_scope, in: %i[shared per_user],
                               default: :shared, predicates: { prefix: true }, scope: true

  # Polymorphic scope (Company or Project, null for internal)
  belongs_to :scope, polymorphic: true, optional: true

  # Owning integration for managed servers
  belongs_to :integration, optional: true

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
  validates :scope, presence: true, if: -> { custom? || managed? }
  validates :integration, presence: true, if: :managed?
  validates :integration, absence:  true, unless: :managed?
  validate :url_safety, if: -> { custom? && url.present? }

  # Scopes
  scope :internal_servers, -> { where(kind: "internal") }
  scope :custom_servers, -> { where(kind: "custom") }
  scope :managed_servers, -> { where(kind: "managed") }
  scope :for_company, ->(company) { custom_servers.where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { custom_servers.where(scope_type: "Project", scope_id: project.id) }
  scope :for_integration, ->(integration) { where(integration_id: integration.id) }
  scope :enabled, -> { where(enabled: true) }

  # Visibility includes internal servers, plus any custom / managed server scoped
  # to the same Company or Project. Managed servers (e.g. Coder integrations)
  # surface alongside custom ones because they share the same scope semantics.
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

  # Convenience predicate for the delivery/UI layer.
  def oauth? = auth_type_oauth?

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
    UrlSafetyValidator.errors_for(url, require_https: auth_type_oauth?).each { |msg| errors.add(:url, msg) }
  end
end
