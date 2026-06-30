# frozen_string_literal: true

class BoardViewPresetResource < ApplicationResource
  attributes :id, :name, :shared, :user_id, :created_at

  typelize "Record<string, unknown>"
  attribute :filters do |preset|
    preset.filters
  end
end
