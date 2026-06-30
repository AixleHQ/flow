# frozen_string_literal: true

class PickerResource < ApplicationResource
  typelize :number
  attribute :id do |record|
    record.id
  end

  typelize :string
  attribute :name do |record|
    record.picker_name
  end
end
