# frozen_string_literal: true

class AgentSerializer < ApplicationSerializer
  include ScopeIndicatorSerialization

  attributes :id, :name, :title, :icon, :persona, :communication_style,
             :principles, :source, :scope_type, :scope_id,
             :created_at, :updated_at
end
