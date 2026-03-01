# frozen_string_literal: true

class ColumnTransition < ApplicationRecord
  extend Enumerize

  belongs_to :board_task
  belongs_to :from_column, class_name: "BoardColumn", optional: true
  belongs_to :to_column, class_name: "BoardColumn"
  belongs_to :actor, class_name: "User"
  belongs_to :workflow_run, optional: true

  enumerize :actor_type, in: %i[human agent auto_trigger]

  validates :actor_type, presence: true

  def self.timestamp_attributes_for_update
    []
  end
end
