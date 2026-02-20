# frozen_string_literal: true

# ToolFile — file to mount into container at tool execution time
class ToolFile < ApplicationRecord
  belongs_to :tool

  validates :path, presence: true,
                   format: { with: %r{\A/workspace/.+\z}, message: "must start with /workspace/" },
                   uniqueness: { scope: :tool_id, message: "already exists for this tool" }
  validates :content, presence: true

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[path created_at updated_at]
  end
end
