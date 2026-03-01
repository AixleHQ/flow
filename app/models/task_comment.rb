# frozen_string_literal: true

class TaskComment < ApplicationRecord
  extend Enumerize

  belongs_to :board_task
  belongs_to :author, class_name: "User"

  enumerize :author_type, in: %i[human agent system], default: :human

  validates :body, presence: true

  scope :with_tag, ->(tag) { where("? = ANY(tags)", tag) }
  scope :by_author_type, ->(type) { where(author_type: type) }

  class << self
    def timestamp_attributes_for_update
      []
    end

    def ransackable_attributes(_auth_object = nil)
      %w[body author_id author_type created_at]
    end

    def ransackable_associations(_auth_object = nil)
      %w[board_task author]
    end
  end
end
