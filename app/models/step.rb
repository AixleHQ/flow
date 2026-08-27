# frozen_string_literal: true

class Step < ApplicationRecord
  extend Enumerize

  SUPPORTED_AGENT_RUNTIMES = %w[claude_code cursor_cli codex gemini_cli].freeze

  belongs_to :workflow
  belongs_to :agent, optional: true

  has_many :step_runs, dependent: :destroy
  has_many :sub_steps, -> { order(:position) }, dependent: :destroy

  accepts_nested_attributes_for :sub_steps, allow_destroy: true

  enumerize :skip_policy, in: %i[never if_outputs_exist manual], default: :never
  enumerize :on_failure, in: %i[retry skip fail], default: :fail

  validates :name, presence: true
  validates :position, presence: true, uniqueness: { scope: :workflow_id }
  validates :preferred_model, format: { with: /\A[a-z0-9][a-z0-9._:-]*\z/, message: "invalid model ID format" }, allow_nil: true
  validates :required_agent_runtime, inclusion: { in: SUPPORTED_AGENT_RUNTIMES }, allow_nil: true
  validate :depends_on_step_ids_valid
  validate :config_item_ids_belong_to_project

  default_scope { order(:position) }

  scope :not_deleted, -> { where(deleted_at: nil) }

  def soft_delete!
    update_column(:deleted_at, Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def destroy
    dependent = workflow.steps.not_deleted.where.not(id: id)
                        .where("depends_on_step_ids @> ?::jsonb", [ id ].to_json)
    if dependent.any?
      errors.add(:base, "Cannot delete step: #{dependent.pluck(:name).join(', ')} depend on it")
      return false
    end

    if step_runs.exists?
      soft_delete!
      self
    else
      super
    end
  end

  def dependency_steps
    return Step.none if depends_on_step_ids.blank?

    workflow.steps.not_deleted.where(id: depends_on_step_ids)
  end

  def root?
    depends_on_step_ids.blank?
  end

  private

  # A step may only name config items of its workflow's own project — the ids
  # decide what `get_config_item` will decrypt for the step's session, so they
  # are never taken on trust from the request that set them.
  def config_item_ids_belong_to_project
    return if config_item_ids.blank?

    unless workflow&.scope_type == "Project"
      errors.add(:config_item_ids, "can only be set on a project-scoped workflow")
      return
    end

    owned = ConfigItem.where(scope_type: "Project", scope_id: workflow.scope_id, id: config_item_ids).pluck(:id)
    foreign = config_item_ids.map(&:to_i) - owned
    return if foreign.empty?

    errors.add(:config_item_ids, "contains items outside this project: #{foreign.sort.join(', ')}")
  end

  def depends_on_step_ids_valid
    return if depends_on_step_ids.blank?

    if depends_on_step_ids.include?(id)
      errors.add(:depends_on_step_ids, "cannot include self")
      return
    end

    sibling_ids = workflow.steps.not_deleted.where.not(id: id).pluck(:id)
    invalid_ids = depends_on_step_ids - sibling_ids
    if invalid_ids.any?
      errors.add(:depends_on_step_ids, "contains invalid step ids: #{invalid_ids.join(', ')}")
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name position created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[workflow agent sub_steps]
  end
end
