# frozen_string_literal: true

# McpServer — MCP (Model Context Protocol) server configuration
#
# kind: internal | custom
# - internal: system-provided by Aixle (e.g., aixle-tools), no scope
# - custom:   user-configured servers (Context7, Tavily, etc.), Project-scoped only
#
# Integration-provided tools (Slack, Coder, ...) are NOT modelled as MCP servers;
# they surface in-process through the internal aixle-tools server, gated on the
# project having an active integration (see `requires_integration` on the tool).
#
# scope: Project only (polymorphic, null for internal)
class MCPServer < ApplicationRecord
  extend Enumerize

  enumerize :kind, in: %i[internal custom], default: :custom, predicates: true
  enumerize :transport, in: %i[http sse stdio], default: :http
  enumerize :auth_type, in: %i[none static oauth],
                        default: :none, predicates: { prefix: true }, scope: true
  enumerize :credential_scope, in: %i[shared per_user],
                               default: :shared, predicates: { prefix: true }, scope: true

  # Polymorphic scope (Project, null for internal)
  belongs_to :scope, polymorphic: true, optional: true

  # OAuth credentials attached to this server (auth_type:oauth). dependent: :destroy
  # so deleting the server cleans them up — the FK is RESTRICT, so without this a
  # server with credentials could not be destroyed. Also lets the index eager-load
  # them (avoids an N+1 in MCPServerResource#oauth_status).
  has_many :oauth_credentials, dependent: :destroy

  # `name` is a free-form human label — no format constraint. The lowercase
  # protocol identifier is derived from it at config-generation time (config_key),
  # NOT stored, so the name is kept verbatim as the user typed it.
  def self.config_key_for(raw)
    raw.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, "_").gsub(/\A[_-]+|[_-]+\z/, "")
  end

  # The MCP protocol key written to each agent's config: the JSON key in .mcp.json
  # and the tool-permission namespace `mcp__<key>__tool`. Existing slug names
  # (already within [a-z0-9_-]) pass through unchanged, so keys like "aixle-tools"
  # stay stable; spaces/punctuation in a free-form name collapse to "_".
  def config_key
    self.class.config_key_for(name)
  end

  # Validations
  validates :name, presence: true
  validates :name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :kind, presence: true
  validates :url, presence: true, if: -> { custom? && !transport_stdio? }
  validates :command, presence: true, if: :transport_stdio?
  validates :scope, presence: true, if: :custom?
  validates :scope_type, inclusion: { in: %w[Project], message: "must be a project" }, if: :custom?
  validate :url_safety, if: -> { custom? && url.present? }

  # Scopes
  scope :internal_servers, -> { where(kind: "internal") }
  scope :custom_servers, -> { where(kind: "custom") }
  scope :for_project, ->(project) { custom_servers.where(scope_type: "Project", scope_id: project.id) }
  scope :enabled, -> { where(enabled: true) }

  # Visibility includes internal servers plus any custom server scoped to the
  # given project. MCP servers exist only at Project scope (or as internal).
  scope :visible_for_project, ->(project) {
    enabled.internal_servers
           .or(enabled.where(scope_type: "Project", scope_id: project.id))
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

  # ----- Connector catalog provenance -----
  # Null for hand-authored servers; set when installed from the public catalog.

  def from_connector?
    connector_name.present?
  end

  # The target (remote endpoint / package) actually chosen at install time.
  # A connector usually offers several, so the snapshot records the one used.
  def installed_connector_target
    connector_manifest["installed_target"] if from_connector?
  end

  # Whether the launched package is locked to an immutable version.
  #
  # False means the registry itself published an unpinnable version (`latest`
  # occurs in real payloads), so the package runner may resolve a different
  # release at any session start. Installing these is allowed on purpose — the
  # catalog does not gatekeep — but the state must stay visible, since an
  # unpinned install is exactly the one a rug pull can move under us.
  # Remote connectors have no package to pin, so the question does not apply.
  def connector_version_pinned?
    target = installed_connector_target
    return true if target.blank? || target["kind"] != "package"

    target["version_pinned"] == true
  end

  # ----- Tool baseline / drift -----

  # Whether this server's declared tools have been recorded at all. stdio
  # servers never have one (they are not probed here), so absence is normal
  # rather than a failure — the UI must not read it as "verified".
  def tool_baseline?
    tool_snapshot_at.present?
  end

  def tool_drift?
    tool_drift.present?
  end

  # Names of tools whose description or schema moved after approval — the
  # rug-pull shape, and the part of drift that warrants the loudest warning.
  def drifted_tool_names
    Array(tool_drift["changed"])
  end

  def picker_name
    name
  end

  def scope_indicator
    return "internal" if internal?
    "project"
  end

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[name kind scope_type enabled created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end

  private

  def url_safety
    UrlSafetyValidator.errors_for(url, require_https: auth_type_oauth?).each { |msg| errors.add(:url, msg) }
  end
end
