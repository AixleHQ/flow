# frozen_string_literal: true

class AssetResource < ApplicationResource
  attributes :id, :name, :folder, :tags, :public,
             :scope_type, :scope_id, :status,
             :created_by_id, :step_run_id,
             :created_at, :updated_at

  attribute :versions_count do |asset|
    asset.versions.size
  end

  attribute :latest_version do |asset|
    version = asset.versions.max_by(&:version)
    next nil unless version

    AssetVersionResource.new(version).to_h
  end

  attribute :created_by_name do |asset|
    asset.created_by&.name
  end

  attribute :scope_indicator do |asset|
    asset.scope_type == "Company" ? "company" : "project"
  end
end
