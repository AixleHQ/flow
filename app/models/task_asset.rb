# frozen_string_literal: true

class TaskAsset < ApplicationRecord
  extend Enumerize
  include TaskAssetUploader::Attachment(:file)

  belongs_to :board_task
  belongs_to :author, class_name: "User"

  enumerize :author_type, in: %i[human agent system], default: :human

  validates :name, presence: true

  scope :with_tag, ->(tag) { where("? = ANY(tags)", tag) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name author_id author_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[board_task author]
  end
end
