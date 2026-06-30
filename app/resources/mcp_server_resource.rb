# frozen_string_literal: true

class MCPServerResource < ApplicationResource
  preserve_keys :env, :headers

  typelize headers: "Record<string, unknown>", env: "Record<string, unknown>", integration_id: :number?
  attributes :id, :name, :display_name, :url, :transport, :headers,
             :description, :kind, :scope_type, :scope_id, :enabled,
             :command, :env, :integration_id, :created_at, :updated_at

  typelize :boolean
  attribute :internal do |server|
    server.internal?
  end

  typelize :boolean
  attribute :managed do |server|
    server.managed?
  end

  typelize %w[internal company project]
  attribute :scope_indicator do |server|
    server.scope_indicator
  end
end
