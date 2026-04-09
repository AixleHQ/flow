# frozen_string_literal: true

class PickerResource < ApplicationResource
  attributes :id

  attribute :name do |record|
    record.picker_name
  end
end
