# frozen_string_literal: true

class ConfigItemSerializer < ApplicationSerializer
  attributes :id, :name, :description, :item_type, :scope_type, :scope_id,
             :value, :value_editable, :created_at, :updated_at

  # Value: show actual for variables, masked for secrets
  def value
    object.display_value
  end

  # Flag for UI to know if value is editable
  def value_editable
    object.value_editable?
  end
end
