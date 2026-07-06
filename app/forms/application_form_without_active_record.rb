# frozen_string_literal: true

module ApplicationFormWithoutActiveRecord
  extend ActiveSupport::Concern

  included do
    include ActiveModel::Model
    include ActiveModel::Attributes
    include ActiveModel::Serialization
  end

  def persisted?
    false
  end
end
