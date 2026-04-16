# frozen_string_literal: true

class MCPServerResource < ApplicationResource
  preserve_keys :env, :headers

  attributes :id, :name, :display_name, :url, :transport, :headers,
             :description, :kind, :scope_type, :scope_id, :enabled,
             :command, :env, :created_at, :updated_at

  attribute :internal do |server|
    server.internal?
  end

  attribute :scope_indicator do |server|
    server.scope_indicator
  end
end
