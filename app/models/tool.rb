# frozen_string_literal: true

# Tool — definition for executable tools
#
# kind:
# - custom:   user-created, scoped to Company or Project
# - system:   platform-provided "big" tools, visible in UI, attached explicitly
# - internal: invisible helpers, auto-injected when session has container tools (read_tool_result)
# - workflow: invisible, auto-injected only in workflow_step sessions (list_sub_steps, mark_sub_step)
# - meta:     meta-workflow tools (meta_*) used ONLY by the Aixle Builder; hidden from
#             normal tool pickers (excluded from visible_for_project/visible_for_company)
#
# execution_mode: app | container
# - app:       executes in Rails process (InternalToolExecutor), synchronous
# - container: runs in Docker via Temporal workflow, async
#
# scope: Company | Project (polymorphic, null for system/internal/workflow)
class Tool < ApplicationRecord
  extend Enumerize

  enumerize :kind, in: %i[custom system internal workflow meta], default: :custom, predicates: true
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
  validates :kind, presence: true
  validates :scope, presence: true, if: :custom?
  validates :docker_image, presence: true, if: :custom?

  # Scopes
  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :custom_tools, -> { where(kind: "custom") }
  scope :system_tools, -> { where(kind: "system") }
  scope :internal_tools, -> { where(kind: "internal") }
  scope :workflow_tools, -> { where(kind: "workflow") }
  scope :session_lifecycle_tools, -> { where(name: %w[finish_session fail_session]).enabled }

  scope :for_company, ->(company) { not_deleted.custom_tools.where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { not_deleted.custom_tools.where(scope_type: "Project", scope_id: project.id) }
  scope :enabled, -> { where(enabled: true) }

  # Tools visible in UI management (system + custom, not internal/workflow)
  scope :ui_visible, -> { where(kind: %w[custom system]) }
  # NOTE: only system/internal/workflow platform kinds are listed here, so :meta
  # tools (Aixle Builder meta_* tools) are intentionally excluded from pickers.
  scope :visible_for_project, ->(project) {
    not_deleted.enabled.where(kind: %w[system internal workflow])
               .or(not_deleted.enabled.where(scope_type: "Company", scope_id: project.company_id))
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
  # Like visible_for_project, :meta tools are excluded (only system/internal/workflow).
  scope :visible_for_company, ->(company) {
    not_deleted.enabled.where(kind: %w[system internal workflow])
               .or(not_deleted.enabled.where(scope_type: "Company", scope_id: company.id))
  }

  def picker_name
    display_name.presence || name
  end

  def scope_indicator
    return "system" if platform_tool?
    scope_type == "Company" ? "company" : "project"
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

  # True for kinds not owned by users (system, internal, workflow)
  def platform_tool?
    !custom?
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  private

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
    %w[name display_name kind scope_type enabled deleted_at created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope tool_files]
  end
end
