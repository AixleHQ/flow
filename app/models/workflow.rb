# frozen_string_literal: true

class Workflow < ApplicationRecord
  belongs_to :scope, polymorphic: true, optional: true
  belongs_to :published_by, class_name: "User", optional: true

  has_many :steps, dependent: :destroy
  has_many :runs, class_name: "WorkflowRun", dependent: :destroy
  has_many :column_workflow_bindings
  has_many :trigger_bindings, dependent: :destroy

  before_destroy :purge_steps, prepend: true
  before_destroy :check_column_bindings

  ALLOWED_CONFIG_KEYS = %w[
    base_tool_ids base_skill_ids base_mcp_server_ids
    base_asset_ids inherit_all_project_resources
  ].freeze

  validates :name, presence: true
  validates :name, uniqueness: { scope: %i[scope_type scope_id], conditions: -> { where(deleted_at: nil) },
                                 message: "already exists in this scope" }
  validates :scope_type, presence: true, inclusion: { in: %w[Project System] }
  validates :scope, presence: true, unless: -> { scope_type == "System" }
  validate :config_keys_whitelist

  scope :active, -> { where(deleted_at: nil) }
  scope :published, -> { where.not(published_at: nil) }
  scope :published_in_company, ->(company) { active.published.belonging_to_company(company) }
  scope :system, -> { where(scope_type: "System") }
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }

  scope :visible_for_project, ->(project) {
    active.where(scope_type: "Project", scope_id: project.id)
  }
  # Every workflow this company can see: the workflows of all its projects.
  scope :belonging_to_company, ->(company) {
    active.where(scope_type: "Project", scope_id: company.project_ids)
  }

  def soft_delete!
    if column_workflow_bindings.any?
      bound = column_workflow_bindings.includes(board_column: { board: :project })
      descs = bound.map { |b| "'#{b.board_column.name}' in project '#{b.board_column.board.project.name}'" }
      raise ActiveRecord::RecordNotDestroyed, "Cannot delete — bound to column #{descs.join(', ')}"
    end
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def published?
    published_at.present?
  end

  def publish!(user)
    update!(published_at: Time.current, published_by: user)
  end

  def unpublish!
    update!(published_at: nil, published_by: nil)
  end

  def has_active_runs?
    runs.where(state: %w[running paused]).exists?
  end

  def scope_indicator
    return "system" if scope_type == "System"

    "project"
  end

  def system?
    scope_type == "System"
  end

  def self.aixle_builder
    system.active.find_by!(name: "Aixle Builder")
  end

  def base_tool_ids
    config&.dig("base_tool_ids") || []
  end

  def base_skill_ids
    config&.dig("base_skill_ids") || []
  end

  def base_mcp_server_ids
    config&.dig("base_mcp_server_ids") || []
  end

  def base_asset_ids
    config&.dig("base_asset_ids") || []
  end

  def inherit_all_project_resources
    config&.dig("inherit_all_project_resources") || false
  end

  def merge_config!(updates)
    self.config = (config || {}).merge(updates.stringify_keys)
    save!
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name description scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end

  private

  def config_keys_whitelist
    return if config.blank?

    unknown = config.keys - ALLOWED_CONFIG_KEYS
    errors.add(:config, "contains unknown keys: #{unknown.join(', ')}") if unknown.any?
  end

  def purge_steps
    step_ids = steps.pluck(:id)
    return if step_ids.empty?

    sub_step_ids = SubStep.where(step_id: step_ids).pluck(:id)
    SubStepRun.where(sub_step_id: sub_step_ids).delete_all if sub_step_ids.any?
    SubStep.where(step_id: step_ids).delete_all
    StepRun.where(step_id: step_ids).delete_all
    Step.where(id: step_ids).delete_all
  end

  def check_column_bindings
    return if column_workflow_bindings.empty?

    bound = column_workflow_bindings.includes(board_column: { board: :project })
    descs = bound.map { |b| "'#{b.board_column.name}' in project '#{b.board_column.board.project.name}'" }
    errors.add(:base, "Cannot delete — bound to column #{descs.join(', ')}")
    throw(:abort)
  end
end
