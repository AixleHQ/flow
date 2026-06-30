# frozen_string_literal: true

class BoardPresetResource < ApplicationResource
  typelize :string
  attribute :key do |preset|
    preset.key
  end

  typelize :string
  attribute :display_name do |preset|
    preset.display_name
  end

  typelize "string[]"
  attribute :columns do |preset|
    preset.columns
  end
end
