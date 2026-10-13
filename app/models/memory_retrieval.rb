# frozen_string_literal: true

class MemoryRetrieval < ApplicationRecord
  belongs_to :project
  belongs_to :terminal_session
  belongs_to :project_memory
  validates :revision, :title, :content, presence: true
  validates :kind, inclusion: { in: %w[search detail] }
end
