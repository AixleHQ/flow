# frozen_string_literal: true

class AgentSerializer < ApplicationSerializer
  attributes :id, :name, :title, :icon, :persona, :communication_style,
             :principles, :source, :scope_type, :scope_id, :scope_indicator,
             :created_at, :updated_at

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
