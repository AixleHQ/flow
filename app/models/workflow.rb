# frozen_string_literal: true

class Workflow < ApplicationRecord
  belongs_to :scope, polymorphic: true, optional: true

  has_many :steps, dependent: :destroy
  has_many :runs, class_name: "WorkflowRun", dependent: :destroy
  has_many :column_workflow_bindings

  before_destroy :check_column_bindings

  ALLOWED_CONFIG_KEYS = %w[
    base_tool_ids base_skill_ids base_mcp_server_ids
    base_asset_ids inherit_all_project_resources
  ].freeze

  validates :name, presence: true
  validates :name, uniqueness: { scope: %i[scope_type scope_id], conditions: -> { where(deleted_at: nil) },
                                 message: "already exists in this scope" }
  validates :scope, presence: true, unless: -> { scope_type == "System" }
  validate :config_keys_whitelist

  scope :active, -> { where(deleted_at: nil) }
  scope :system, -> { where(scope_type: "System") }
  scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }

  scope :visible_for_project, ->(project) {
    active.where(scope_type: "Project", scope_id: project.id)
          .or(active.where(scope_type: "Company", scope_id: project.company_id))
  }
  scope :visible_for_company, ->(company) { active.for_company(company) }
  scope :belonging_to_company, ->(company) {
    active.where(scope_type: "Company", scope_id: company.id)
          .or(active.where(scope_type: "Project", scope_id: company.project_ids))
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

  def has_active_runs?
    runs.where(state: %w[running paused]).exists?
  end

  def scope_indicator
    return "system" if scope_type == "System"

    scope_type == "Company" ? "company" : "project"
  end

  def system?
    scope_type == "System"
  end

  def self.palad_builder
    system.active.find_by!(name: "Palad Builder")
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

  def check_column_bindings
    return if column_workflow_bindings.empty?

    bound = column_workflow_bindings.includes(board_column: { board: :project })
    descs = bound.map { |b| "'#{b.board_column.name}' in project '#{b.board_column.board.project.name}'" }
    errors.add(:base, "Cannot delete — bound to column #{descs.join(', ')}")
    throw(:abort)
  end
end
