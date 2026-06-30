# frozen_string_literal: true

class ConfigItemResource < ApplicationResource
  attributes :id, :name, :description, :item_type, :scope_type, :created_at, :updated_at

  attribute :value do |item|
    item.display_value
  end

  typelize %w[company project]
  attribute :scope_indicator do |item|
    item.scope_indicator
  end
end
