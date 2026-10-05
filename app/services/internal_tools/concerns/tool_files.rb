# frozen_string_literal: true

module InternalTools
  module Concerns
    # The `files` argument of the message tools: each entry names exactly one
    # source of bytes — inline text, a path in the running container, or a
    # project asset — and comes back as { filename:, content:, title: }.
    module ToolFiles
      private

      # Returns [resolved_array, error]: on the first unresolvable entry,
      # resolved_array is nil and error is a tool error.
      def build_files
        resolved = []
        Array(params[:files]).each_with_index do |raw, index|
          f = raw.respond_to?(:to_h) ? raw.to_h.with_indifferent_access : {}
          entry, err = resolve_file_entry(f, index)
          return [ nil, err ] if err

          resolved << entry
        end
        [ resolved, nil ]
      end

      def resolve_file_entry(f, index)
        sources = %i[content file_path asset_id].select { |k| f[k].present? }
        return [ nil, error("files[#{index}] needs one of: content, file_path, asset_id") ] if sources.empty?
        return [ nil, error("files[#{index}] must set only one of content/file_path/asset_id") ] if sources.size > 1

        title = f[:title].presence
        case sources.first
        when :content    then resolve_inline_file(f, index, title)
        when :file_path  then resolve_container_file(f, index, title)
        when :asset_id   then resolve_asset_file(f, index, title)
        end
      end

      def resolve_inline_file(f, index, title)
        filename = f[:filename].presence
        return [ nil, error("files[#{index}] with content requires filename") ] if filename.blank?

        [ { filename: filename, content: f[:content].to_s, title: title }, nil ]
      end

      def resolve_container_file(f, index, title)
        container_id = session.try(:container_id)
        return [ nil, error("No container available to read file from") ] if container_id.blank?

        path = f[:file_path].to_s
        bytes = ContainerRuntime.build.read_file(container_id, path)
        return [ nil, error("files[#{index}] file not found in container: #{path}") ] if bytes.nil?

        filename = f[:filename].presence || File.basename(path)
        [ { filename: filename, content: bytes, title: title }, nil ]
      end

      def resolve_asset_file(f, index, title)
        return [ nil, error("No project in the current context") ] if project.nil?

        asset = Asset.accessible_from_project(project).find_by(id: f[:asset_id])
        return [ nil, error("files[#{index}] asset not found in this project: #{f[:asset_id]}") ] if asset.nil?

        version = asset.latest_version
        return [ nil, error("files[#{index}] asset ##{asset.id} has no file content") ] if version&.file.nil?

        bytes = version.file.download { |file| file.read }
        filename = f[:filename].presence || asset.name
        [ { filename: filename, content: bytes, title: title }, nil ]
      end
    end
  end
end
