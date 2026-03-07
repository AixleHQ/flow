# frozen_string_literal: true

class MCPServerSerializer < ApplicationSerializer
  include ScopeIndicatorSerialization

  attributes :id, :name, :display_name, :url, :transport, :headers, :description,
             :kind, :scope_type, :scope_id, :enabled, :internal,
             :command, :env, :created_at, :updated_at

  def internal
    object.internal?
  end
end
