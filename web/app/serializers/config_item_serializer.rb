# frozen_string_literal: true

class ConfigItemSerializer < ApplicationSerializer
  attributes :id, :name, :description, :item_type, :scope_type, :scope_id,
             :value, :value_editable, :scope_indicator, :created_at, :updated_at

  # Value: show actual for variables, masked for secrets
  def value
    object.display_value
  end

  # Flag for UI to know if value is editable
  def value_editable
    object.value_editable?
  end

  # Scope indicator for merged list
  # Returns: "company", "project", or "overrides_company"
  def scope_indicator
    if object.respond_to?(:scope_indicator)
      object.scope_indicator
    elsif object.scope_type == "Company"
      "company"
    else
      "project"
    end
  end
end
