# frozen_string_literal: true

class AssetResource < ApplicationResource
  attributes :id, :name, :folder, :tags, :public,
             :scope_type, :scope_id, :status,
             :created_by_id, :step_run_id,
             :created_at, :updated_at

  typelize :number
  attribute :versions_count do |asset|
    asset.versions.size
  end

  typelize "AssetVersion | null"
  attribute :latest_version do |asset|
    version = asset.versions.max_by(&:version)
    next nil unless version

    AssetVersionResource.new(version).to_h
  end

  typelize :string?
  attribute :created_by_name do |asset|
    asset.created_by&.name
  end

  typelize %w[company project]
  attribute :scope_indicator do |asset|
    asset.scope_type == "Company" ? "company" : "project"
  end
end
