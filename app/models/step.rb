# frozen_string_literal: true

class Step < ApplicationRecord
  extend Enumerize

  belongs_to :workflow
  belongs_to :agent, optional: true

  has_many :step_runs, dependent: :destroy
  has_many :sub_steps, -> { order(:position) }, dependent: :destroy

  accepts_nested_attributes_for :sub_steps, allow_destroy: true

  enumerize :skip_policy, in: %i[never if_outputs_exist manual], default: :never
  enumerize :on_failure, in: %i[retry skip fail], default: :fail

  validates :name, presence: true
  validates :position, presence: true, uniqueness: { scope: :workflow_id }
  validate :depends_on_step_ids_valid

  default_scope { order(:position) }

  scope :active, -> { where(deleted_at: nil) }

  def soft_delete!
    update_column(:deleted_at, Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def destroy
    if step_runs.exists?
      soft_delete!
      self
    else
      super
    end
  end

  def dependency_steps
    return Step.none if depends_on_step_ids.blank?

    workflow.steps.active.where(id: depends_on_step_ids)
  end

  def root?
    depends_on_step_ids.blank?
  end

  private

  def depends_on_step_ids_valid
    return if depends_on_step_ids.blank?

    if depends_on_step_ids.include?(id)
      errors.add(:depends_on_step_ids, "cannot include self")
      return
    end

    sibling_ids = workflow.steps.active.where.not(id: id).pluck(:id)
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
