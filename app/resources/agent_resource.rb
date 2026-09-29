# frozen_string_literal: true

class AgentResource < ApplicationResource
  attributes :id, :name, :title, :icon, :persona, :communication_style,
             :principles, :source, :scope_type, :scope_id,
             :current_version_number, :archived_at, :created_at, :updated_at

  typelize %w[system company project]
  attribute :scope_indicator do |agent|
    agent.scope_indicator
  end
end
