# frozen_string_literal: true

class AssetSerializer < ApplicationSerializer
  attributes :id, :name, :folder, :tags, :public,
             :scope_type, :scope_id, :scope_indicator,
             :created_by_id, :step_run_id,
             :latest_version, :versions_count,
             :deleted_at, :created_at, :updated_at

  def scope_indicator
    if object.respond_to?(:scope_indicator)
      object.scope_indicator
    elsif object.scope_type == "Company"
      "company"
    else
      "project"
    end
  end

  def latest_version
    version = object.latest_version
    return nil unless version

    {
      id: version.id,
      version: version.version,
      content_type: version.content_type,
      file_size: version.file_size,
      uploaded_by_id: version.uploaded_by_id,
      source: version.source,
      file_url: version.file&.url,
      created_at: version.created_at
    }
  end

  def versions_count
    object.versions.size
  end
end
