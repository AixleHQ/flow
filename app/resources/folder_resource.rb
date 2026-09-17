# frozen_string_literal: true

class FolderResource < ApplicationResource
  attributes :id, :path, :scope_type, :created_at, :updated_at

  typelize %w[company project]
  attribute :scope_indicator do |folder|
    folder.scope_indicator
  end
end
