# frozen_string_literal: true

class ConfigItemSerializer < ApplicationSerializer
  include ScopeIndicatorSerialization

  attributes :id, :name, :description, :item_type, :scope_type, :scope_id,
             :value, :value_editable, :created_at, :updated_at

  def value
    object.display_value
  end

  def value_editable
    object.value_editable?
  end
end
