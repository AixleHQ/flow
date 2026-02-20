# frozen_string_literal: true

class MCPServerSerializer < ApplicationSerializer
  attributes :id, :name, :display_name, :url, :transport, :headers, :description,
             :kind, :scope_type, :scope_id, :enabled, :scope_indicator, :internal,
             :created_at, :updated_at

  # Scope indicator for merged list
  def scope_indicator
    if object.respond_to?(:scope_indicator)
      object.scope_indicator
    elsif object.internal?
      "internal"
    elsif object.scope_type == "Company"
      "company"
    else
      "project"
    end
  end

  def internal
    object.internal?
  end
end
