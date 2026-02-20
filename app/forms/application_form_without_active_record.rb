# frozen_string_literal: true

module ApplicationFormWithoutActiveRecord
  extend ActiveSupport::Concern

  included do
    include ActiveModel::Validations
    include ActiveModel::Conversion
    include ActiveModel::Serialization
    include ::Virtus.model
  end

  def persisted?
    false
  end
end
