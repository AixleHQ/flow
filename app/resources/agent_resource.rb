# frozen_string_literal: true

class AgentResource < ApplicationResource
  attributes :id, :name, :title, :icon, :persona, :communication_style,
             :principles, :source, :scope_type, :scope_id,
             :created_at, :updated_at

  attribute :scope_indicator do |agent|
    agent.scope_indicator
  end
end
