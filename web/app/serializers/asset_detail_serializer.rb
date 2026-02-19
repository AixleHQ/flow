# frozen_string_literal: true

class AssetDetailSerializer < AssetSerializer
  attributes :versions

  def versions
    object.versions.order(version: :desc).map do |v|
      {
        id: v.id,
        version: v.version,
        content_type: v.content_type,
        file_size: v.file_size,
        uploaded_by_id: v.uploaded_by_id,
        source: v.source,
        file_url: v.file_url,
        created_at: v.created_at
      }
    end
  end
end
