# frozen_string_literal: true

class Step < ApplicationRecord
  extend Enumerize

  belongs_to :workflow
  belongs_to :agent, optional: true

  has_many :sub_steps, dependent: :destroy

  accepts_nested_attributes_for :sub_steps, allow_destroy: true

  enumerize :skip_policy, in: %i[never if_outputs_exist manual], default: :never
  enumerize :on_failure, in: %i[retry skip fail], default: :fail

  validates :name, presence: true
  validates :position, presence: true, uniqueness: { scope: :workflow_id }

  default_scope { order(:position) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name position created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[workflow agent sub_steps]
  end
end
