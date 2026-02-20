# frozen_string_literal: true

class ToolFileSerializer < ApplicationSerializer
  attributes :id, :path, :content, :created_at, :updated_at
end
