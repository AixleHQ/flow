# frozen_string_literal: true

class AssetVersion < ApplicationRecord
  include AssetFileUploader::Attachment(:file)

  belongs_to :asset
  belongs_to :uploaded_by, class_name: "User"

  validates :version, presence: true

  before_validation :set_version, on: :create

  private

  def set_version
    self.version = (asset&.versions&.maximum(:version) || 0) + 1
  end
end
