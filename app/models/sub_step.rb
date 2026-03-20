# frozen_string_literal: true

class SubStep < ApplicationRecord
  belongs_to :step
  has_many :sub_step_runs

  validates :name, presence: true
  validates :position, presence: true

  default_scope { where(deleted_at: nil).order(:position) }

  def soft_delete!
    update_column(:deleted_at, Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def destroy
    if sub_step_runs.exists?
      soft_delete!
      self
    else
      super
    end
  end
end
