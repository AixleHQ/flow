# frozen_string_literal: true

class AssetVersion < ApplicationRecord
  extend Enumerize
  include AssetFileUploader::Attachment(:file)

  belongs_to :asset, inverse_of: :versions
  belongs_to :uploaded_by, class_name: "User"

  enumerize :source, in: %i[upload workflow github session], default: :upload, predicates: true

  validates :version, presence: true

  before_validation :set_version, on: :create

  def self.ransackable_attributes(_auth_object = nil)
    %w[id asset_id version source uploaded_by_id created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[asset uploaded_by]
  end

  private

  def set_version
    self.version = (asset&.versions&.maximum(:version) || 0) + 1
  end
end
