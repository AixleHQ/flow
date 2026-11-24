# frozen_string_literal: true

class SubStep < ApplicationRecord
  include DecodesHtmlEntities

  belongs_to :step
  belongs_to :origin_sub_step, class_name: "SubStep", optional: true
  has_many :sub_step_runs

  decodes_html_entities :name

  validates :name, presence: true
  validates :position, presence: true

  scope :active, -> { where(deleted_at: nil) }

  def soft_delete!
    update_column(:deleted_at, Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # Always a soft delete, for the same reason as Step#destroy.
  def destroy
    soft_delete!
    self
  end
end
