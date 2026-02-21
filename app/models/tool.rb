# frozen_string_literal: true

# Tool — definition for executable tools (internal or custom)
#
# kind: internal | custom
# - internal: system-provided by Palad, no scope, read-only
# - custom: user-created tools with scope (Company or Project)
#
# scope: Company | Project (polymorphic, null for internal)
class Tool < ApplicationRecord
  extend Enumerize

  enumerize :kind, in: %i[internal custom], default: :custom, predicates: true

  # Polymorphic scope (Company or Project, null for internal)
  belongs_to :scope, polymorphic: true, optional: true

  # Files to mount into container
  has_many :tool_files, dependent: :destroy
  accepts_nested_attributes_for :tool_files, allow_destroy: true

  # Auto-downcase name
  def name=(val)
    super(val&.downcase&.gsub(/[^a-z0-9_]/, "_"))
  end

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must start with letter, use lowercase letters, numbers, underscores" }
  validates :name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :display_name, presence: true
  validates :kind, presence: true
  validates :scope, presence: true, if: :custom?
  validates :docker_image, presence: true, if: :custom?

  # Scopes
  scope :internal_tools, -> { where(kind: "internal") }
  scope :custom_tools, -> { where(kind: "custom") }
  scope :for_company, ->(company) { custom_tools.where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { custom_tools.where(scope_type: "Project", scope_id: project.id) }
  scope :enabled, -> { where(enabled: true) }

  # Get merged list of tools for a project (internal + company + project)
  # Returns array with scope_indicator method on each tool
  def self.merged_for_project(project)
    all_internal = internal_tools.enabled.to_a
    company_tools = for_company(project.company).enabled.to_a
    project_tools = for_project(project).enabled.to_a
    project_names = project_tools.map(&:name)

    result = []

    # Add internal tools (always included)
    all_internal.each do |tool|
      tool.define_singleton_method(:scope_indicator) { "internal" }
      result << tool
    end

    # Add project tools (they override company tools)
    project_tools.each do |tool|
      overrides = company_tools.any? { |ct| ct.name == tool.name }
      tool.define_singleton_method(:scope_indicator) { overrides ? "overrides_company" : "project" }
      result << tool
    end

    # Add company tools that are NOT overridden by project
    company_tools.reject { |ct| project_names.include?(ct.name) }.each do |tool|
      tool.define_singleton_method(:scope_indicator) { "company" }
      result << tool
    end

    result.sort_by(&:name)
  end

  # Get merged list for company level (internal + company)
  def self.merged_for_company(company)
    all_internal = internal_tools.enabled.to_a
    company_tools = for_company(company).enabled.to_a

    result = []

    all_internal.each do |tool|
      tool.define_singleton_method(:scope_indicator) { "internal" }
      result << tool
    end

    company_tools.each do |tool|
      tool.define_singleton_method(:scope_indicator) { "company" }
      result << tool
    end

    result.sort_by(&:name)
  end

  WORKFLOW_TIMEOUT = 3600 # 1 hour

  # Execute tool in a container via Temporal (blocking).
  #
  # @param parameters [Hash] Tool parameters
  # @param project [Project, nil] Project context
  # @param timeout [Integer] Execution timeout in seconds
  # @return [Hash] { exit_code:, stdout:, stderr:, duration_ms: }
  def execute(parameters: {}, project: nil, timeout: 300)
    strategy = ContainerStrategies::ToolExecutionStrategy.new(
      tool: self, parameters: parameters, project: project, timeout: timeout
    )

    TemporalService.execute_workflow(
      WorkflowService.container_workflow,
      { tool_id: id, parameters: parameters, project_id: project&.id,
        timeout: timeout, manifest: strategy.build_manifest }
    )
  end

  # Start tool execution async (non-blocking).
  def start_execution(parameters: {}, project: nil, timeout: 300)
    strategy = ContainerStrategies::ToolExecutionStrategy.new(
      tool: self, parameters: parameters, project: project, timeout: timeout
    )
    workflow_id = "tool-execution-#{id}-#{SecureRandom.hex(8)}"

    TemporalService.start_workflow(
      WorkflowService.container_workflow,
      { tool_id: id, parameters: parameters, project_id: project&.id,
        timeout: timeout, manifest: strategy.build_manifest },
      id: workflow_id,
      execution_timeout: WORKFLOW_TIMEOUT
    )
  end

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[name display_name kind scope_type enabled created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope tool_files]
  end
end
