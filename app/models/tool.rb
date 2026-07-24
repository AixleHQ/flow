# frozen_string_literal: true

# Tool — one row per callable tool.
#
# source:
# - db:   user-created custom tool (docker_image + command), Project-scoped,
#         authored via the UI or meta_create_tool
# - code: reconciler-owned shadow row of a code-defined platform tool; the
#         definition (schema, tags, availability, injection) lives on the
#         InternalTools::* class — see Tools::Registry / Tools::Reconciler
#
# Grouping is via `tags` (closed vocabulary in the tool DSL); picker
# visibility via `user_attachable`; auto-injection rules are code-only.
#
# execution_mode: app | container
# - app:       executes in Rails process (InternalToolExecutor), synchronous
# - container: runs in Docker via Temporal workflow, async
class Tool < ApplicationRecord
  extend Enumerize

  enumerize :execution_mode, in: %i[app container], default: :container, predicates: true

  belongs_to :scope, polymorphic: true, optional: true

  has_many :tool_files, dependent: :destroy
  has_many :tool_results, dependent: :destroy
    accepts_nested_attributes_for :tool_files, allow_destroy: true

  def name=(val)
    super(val&.downcase&.gsub(/[^a-z0-9_]/, "_"))
  end

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must start with letter, use lowercase letters, numbers, underscores" }
  validates :name, uniqueness: { scope: %i[scope_type scope_id], conditions: -> { where(deleted_at: nil) },
                                 message: "already exists in this scope" }
  validates :display_name, presence: true
  validates :scope, presence: true, if: :db_source?
  validates :scope_type, inclusion: { in: %w[Project], message: "must be a project" }, if: :db_source?
  validates :docker_image, presence: true, if: :db_source?
  validate :name_outside_platform_namespace, if: -> { db_source? && (new_record? || name_changed?) }
  validate :custom_definition_hygiene, if: :db_source?
  before_save :reset_image_digest, if: -> { db_source? && docker_image_changed? }
  before_save :stamp_definition_digest, if: :db_source?

  # Scopes
  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :code_source, -> { where(source: "code") }
  scope :db_source, -> { where(source: "db") }
  scope :deleted, -> { where.not(deleted_at: nil) }

  scope :for_project, ->(project) { not_deleted.db_source.where(scope_type: "Project", scope_id: project.id) }
  scope :enabled, -> { where(enabled: true) }

  # Tools shown in UI management: user-authored custom tools only. Platform
  # (code) tools are injected/gated automatically and are not managed here.
  scope :ui_visible, -> { db_source }
  # Pickers: attachable platform tools (user_attachable false hides the Aixle
  # Builder meta_* tools) plus in-scope custom tools, gated on the
  # reconciler-owned requires_integration projection.
  scope :visible_for_project, ->(project) {
    not_deleted.enabled.where(source: "code", user_attachable: true)
               .or(not_deleted.enabled.where(scope_type: "Project", scope_id: project.id))
               .where("tools.requires_integration IS NULL OR tools.requires_integration IN (?)",
                      active_integration_providers(project))
  }

  # Providers of integrations active for this project (project-scoped or
  # company-wide). Used to gate tools that require an integration to be usable —
  # e.g. slack_post_message is hidden until Slack is connected.
  def self.active_integration_providers(project)
    return [] if project.nil?

    Integration.active
               .where("(project_id = :pid) OR (project_id IS NULL AND company_id = :cid)",
                      pid: project.id, cid: project.company_id)
               .distinct.pluck(:provider)
  end
  # Projectless sessions can still attach platform (code) tools; custom tools
  # are Project-scoped only, so none surface at the company level.
  scope :visible_for_company, ->(_company) {
    not_deleted.enabled.where(source: "code", user_attachable: true)
  }

  def picker_name
    display_name.presence || name
  end

  def scope_indicator
    return "system" if platform_tool?
    "project"
  end

  WORKFLOW_TIMEOUT = 3600 # 1 hour

  # Execute tool.
  #
  # Routes based on execution_mode:
  # - app       → InternalToolExecutor (Ruby handler, synchronous)
  # - container → Temporal start_workflow (Docker container, async)
  def execute(parameters: {}, project: nil, session: nil, timeout: 300, tool_result_id: nil, mcp_server: nil)
    case execution_mode.to_sym
    when :app
      InternalToolExecutor.execute(self, parameters, session, mcp_server: mcp_server)
    when :container
      start_container_execution(
        parameters: parameters, project: project,
        session: session, timeout: timeout,
        tool_result_id: tool_result_id
      )
    end
  end

  # True for reconciler-owned shadow rows of code-defined tools.
  def platform_tool?
    code_source?
  end

  def code_source?
    source == "code"
  end

  def db_source?
    source == "db"
  end

  # The in-code definition backing this shadow row (nil for user-authored
  # custom tools). Serving paths prefer it over the row's own columns so a
  # stale row between deploy and reconcile can never serve stale metadata.
  def definition
    code_source? ? Tools::Registry.fetch(name) : nil
  end

  # One availability predicate for every surface (tools/list hides,
  # tools/call enforces, pickers keep the equivalent SQL clause over the
  # reconciler-owned requires_integration column).
  def available?(ctx)
    return false unless enabled? && !deleted?

    if (defn = definition)
      defn.available?(ctx)
    elsif requires_integration.present?
      ctx.connected?(requires_integration)
    else
      true
    end
  end

  def unavailable_message
    definition&.unavailable_message ||
      "The #{requires_integration} integration is not connected for this project. " \
      "Connect it in Project Settings → Integrations."
  end

  # Returns the shadow row for a code definition, materializing it on demand.
  # This is what makes "platform tools work without pre-created DB rows"
  # literally true: the class alone suffices; rows appear on first FK need
  # (session attachment, ToolResult creation) even if no reconcile ran yet.
  def self.shadow_for(definition)
    shadow_rows_for_names([ definition.name ]).first ||
      raise(ActiveRecord::RecordNotFound, "No shadow row for tool definition '#{definition.name}'")
  end

  # Batch variant: one query for the common case, one reconcile + refetch
  # when any row hasn't been materialized yet.
  def self.shadow_rows_for_names(names)
    return [] if names.empty?

    rows = not_deleted.code_source.where(name: names).to_a
    if (names - rows.map(&:name)).any?
      Tools::Reconciler.run!
      rows = not_deleted.code_source.where(name: names).to_a
    end
    rows
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # Rug-pull check: true when the stored digest matches the current
  # definition. A write that bypassed validations (update_columns, raw SQL,
  # a compromised console) leaves a mismatch and serving fails closed.
  # Platform rows are code-defined and reconciler-owned — always intact.
  def definition_digest_intact?
    return true if code_source?

    definition_digest.present? && definition_digest == compute_definition_digest
  end

  def compute_definition_digest
    payload = {
      "name" => name,
      "display_name" => display_name,
      "description" => description,
      "command" => command,
      "docker_image" => docker_image,
      "input_schema" => input_schema.as_json,
      "required_config_items" => required_config_items.as_json
    }
    Digest::SHA256.hexdigest(JSON.dump(payload))
  end

  private

  SCHEMA_MAX_BYTES = 64_000
  SCHEMA_MAX_DEPTH = 12
  FORBIDDEN_SCHEMA_KEYS = %w[$ref $defs $dynamicRef $dynamicAnchor].freeze
  INJECTION_PATTERN = /<\s*(important|system|instructions?)\b|ignore\s+(all\s+)?previous\s+instructions/i

  # Publisher-grade hygiene for tenant-authored definitions (they share one
  # tools/list with platform tools — see the registry research, metadata-trust
  # section): meta-valid JSON Schema 2020-12, no $ref family (client-breaking
  # and a DoS surface), bounded size/depth, and no prompt-injection markers in
  # any free-text field the model reads.
  def custom_definition_hygiene
    schema = input_schema.as_json
    return if schema.blank? && description.blank?

    if schema.present?
      errors.add(:input_schema, "exceeds #{SCHEMA_MAX_BYTES} bytes") if JSON.dump(schema).bytesize > SCHEMA_MAX_BYTES
      errors.add(:input_schema, "nests deeper than #{SCHEMA_MAX_DEPTH} levels") if json_depth(schema) > SCHEMA_MAX_DEPTH
      if (bad_key = forbidden_schema_key(schema))
        errors.add(:input_schema, "uses unsupported keyword #{bad_key}")
      end
      errors.add(:input_schema, "is not a valid JSON Schema") if errors[:input_schema].empty? && !JSONSchemer.valid_schema?(schema)
    end

    ([ description ] + schema_texts(schema)).compact.each do |text|
      if text.match?(INJECTION_PATTERN)
        errors.add(:base, "description text contains disallowed instruction-like content")
        break
      end
    end
  end

  def json_depth(value, depth = 1)
    case value
    when Hash then value.values.map { |v| json_depth(v, depth + 1) }.max || depth
    when Array then value.map { |v| json_depth(v, depth + 1) }.max || depth
    else depth
    end
  end

  def forbidden_schema_key(value)
    case value
    when Hash
      value.each do |k, v|
        return k if FORBIDDEN_SCHEMA_KEYS.include?(k.to_s)
        found = forbidden_schema_key(v)
        return found if found
      end
      nil
    when Array
      value.each { |v| (found = forbidden_schema_key(v)) and return found }
      nil
    end
  end

  def schema_texts(value)
    case value
    when Hash
      value.flat_map { |k, v| %w[description title].include?(k.to_s) && v.is_a?(String) ? [ v ] : schema_texts(v) }
    when Array
      value.flat_map { |v| schema_texts(v) }
    else
      []
    end
  end

  def stamp_definition_digest
    self.definition_digest = compute_definition_digest
  end

  # A changed image invalidates the pinned digest; it re-pins on the next
  # execution (ContainerStrategies::CustomToolStrategy).
  def reset_image_digest
    self.docker_image_digest = nil
  end

  # Structural anti-shadowing: a tenant-authored row must never claim a
  # platform tool's name or the managed-MCP namespace. Grandfathered rows are
  # reported by tools:check; this guards creates and renames going forward.
  def name_outside_platform_namespace
    if name&.start_with?("mcp__")
      errors.add(:name, "cannot use the reserved mcp__ namespace")
    elsif Tools::Registry.fetch(name)
      errors.add(:name, "collides with the platform tool '#{name}'")
    end
  end

  def start_container_execution(parameters:, project:, session:, timeout:, tool_result_id:)
    strategy = build_strategy(
      parameters: parameters, project: project,
      session: session, timeout: timeout,
      tool_result_id: tool_result_id
    )
    workflow_id = "tool-exec-#{id}-#{SecureRandom.hex(8)}"

    TemporalService.start_workflow(
      TemporalWorkflowRegistry.container_workflow,
      { tool_id: id, tool_result_id: tool_result_id,
        parameters: parameters, project_id: project&.id,
        timeout: timeout, manifest: strategy.build_manifest },
      id: workflow_id,
      execution_timeout: WORKFLOW_TIMEOUT
    )
  end

  def build_strategy(parameters:, project:, session:, timeout:, tool_result_id:)
    if ContainerStrategies::InternalToolStrategy.registered?(name)
      ContainerStrategies::InternalToolStrategy.build_for(
        name,
        params: parameters,
        session: session,
        tool_result_id: tool_result_id,
        timeout: timeout
      )
    else
      ContainerStrategies::CustomToolStrategy.new(
        tool: self, parameters: parameters, project: project,
        timeout: timeout, tool_result_id: tool_result_id
      )
    end
  end

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[name display_name source scope_type enabled deleted_at created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope tool_files]
  end
end
