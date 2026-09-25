# frozen_string_literal: true

module Versions
  module Snapshots
    # A custom tool plus its files. A text file is kept inline; a binary one by
    # its Shrine reference — ToolFileUploader never deletes stored objects, so a
    # reference in an old snapshot keeps resolving (ToolFiles::OrphanSweep only
    # removes objects nothing points at).
    #
    # `docker_image_digest` is the pin the platform resolves for `docker_image`,
    # and `definition_digest` is derived on save: both are system state.
    class Tool < Base
      FIELDS = %w[name display_name description command docker_image execution_mode input_schema
                  required_config_items requires_integration tags enabled user_attachable].freeze
      EXCLUDED = %w[id source scope_type scope_id project_id company_id docker_image_digest definition_digest
                    deleted_at current_version_number created_at updated_at].freeze
      FILE_FIELDS = %w[path content file_data].freeze
      FILE_EXCLUDED = %w[id tool_id created_at updated_at].freeze

      class << self
        def dump(record)
          files = record.tool_files.reload.sort_by(&:path).map do |file|
            { "path" => file.path, "content" => file.content, "file_data" => parse(file[:file_data]) }
          end
          super.merge("files" => files)
        end

        def restore!(record, snapshot)
          record.assign_attributes(snapshot.slice(*FIELDS))
          wanted = Array(snapshot["files"]).index_by { |f| f["path"] }
          existing = record.tool_files.to_a.index_by(&:path)

          existing.each { |path, file| file.mark_for_destruction unless wanted.key?(path) }
          wanted.each do |path, spec|
            file = existing[path] || record.tool_files.build(path: path)
            file.content = spec["content"]
            file[:file_data] = spec["file_data"]&.to_json
          end
          record.save!
        end

        private

        def parse(file_data)
          file_data.present? ? JSON.parse(file_data) : nil
        end
      end
    end
  end
end
