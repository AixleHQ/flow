# frozen_string_literal: true

class ExternalResource < ApplicationRecord
  self.inheritance_column = nil
  belongs_to :board_task

  validates :type, :external_instance, :external_id, presence: true

  def url
    return unless type == "youtrack_issue" && data["readable_id"].present?
    "#{external_instance}/issue/#{ERB::Util.url_encode(data["readable_id"])}"
  end
end
