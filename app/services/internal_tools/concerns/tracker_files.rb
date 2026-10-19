# frozen_string_literal: true

module InternalTools
  module Concerns
    # The `files` argument of tracker_attach_files: each entry names exactly
    # one source — inline text, a path in the running container, a project
    # asset or a board task's attachment — and becomes a Trackers::UploadFile
    # backed by a temp file. Sizes are checked before bytes are read, so a large
    # file in the container is refused without being pulled into this process.
    module TrackerFiles
      SOURCES = %i[content file_path asset_id task_asset_id].freeze

      private

      # Yields [files, error]; temp files are removed afterwards.
      def with_upload_files(max_bytes:)
        temps = []
        files = []
        Array(params[:files]).each_with_index do |raw, index|
          entry = raw.respond_to?(:to_h) ? raw.to_h.with_indifferent_access : {}
          file, err = upload_file(entry, index, max_bytes, temps)
          return yield(nil, err) if err

          files << file
        end
        yield(files, nil)
      ensure
        temps&.each(&:close!)
      end

      def upload_file(entry, index, max_bytes, temps)
        given = SOURCES.select { |key| entry[key].present? }
        return [ nil, error("files[#{index}] needs one of: #{SOURCES.join(', ')}") ] if given.empty?
        return [ nil, error("files[#{index}] must set only one of #{SOURCES.join('/')}") ] if given.many?

        name, bytes_or_err =
          case given.first
          when :content then read_content(entry, index)
          when :file_path then read_file_path(entry, index, max_bytes)
          when :asset_id then read_asset_id(entry, index, max_bytes)
          else read_task_asset_id(entry, index, max_bytes)
          end
        return [ nil, bytes_or_err ] if bytes_or_err.is_a?(Hash)
        return [ nil, error("files[#{index}] is larger than #{max_bytes / 1.megabyte} MB") ] if bytes_or_err.bytesize > max_bytes

        name = Trackers::Workspace.clean_name(entry[:filename].presence || name)
        [ temp_upload(bytes_or_err, name, temps), nil ]
      end

      def read_content(entry, index)
        return [ nil, error("files[#{index}] with content requires filename") ] if entry[:filename].blank?

        [ entry[:filename], entry[:content].to_s.b ]
      end

      def read_file_path(entry, index, max_bytes)
        container = session.try(:container_id)
        return [ nil, error("No container is running to read files from") ] if container.blank?

        path = entry[:file_path].to_s
        runtime = ContainerRuntime.build
        out, _err, code = runtime.exec(container, [ "stat", "-c", "%s", path ])
        size = Array(out).join.strip
        return [ nil, error("files[#{index}] file not found in the container: #{path}") ] unless code.to_i.zero? && size.match?(/\A\d+\z/)
        return [ nil, error("files[#{index}] is larger than #{max_bytes / 1.megabyte} MB") ] if size.to_i > max_bytes

        bytes = runtime.read_file(container, path)
        return [ nil, error("files[#{index}] could not be read from the container: #{path}") ] if bytes.nil?

        [ File.basename(path), bytes.b ]
      end

      def read_asset_id(entry, index, max_bytes)
        asset = Asset.accessible_from_project(project).find_by(id: entry[:asset_id]) if project
        version = asset&.latest_version
        return [ nil, error("files[#{index}] asset not found in this project: #{entry[:asset_id]}") ] unless version&.file
        return [ nil, error("files[#{index}] is larger than #{max_bytes / 1.megabyte} MB") ] if version.file_size.to_i > max_bytes

        [ asset.name, version.file.download(&:read).b ]
      end

      def read_task_asset_id(entry, index, max_bytes)
        asset = TaskAsset.joins(board_task: :board).find_by(id: entry[:task_asset_id], boards: { project_id: project&.id })
        return [ nil, error("files[#{index}] task attachment not found in this project: #{entry[:task_asset_id]}") ] unless asset&.file
        return [ nil, error("files[#{index}] is larger than #{max_bytes / 1.megabyte} MB") ] if asset.file.size.to_i > max_bytes

        [ asset.name, asset.file.download(&:read).b ]
      end

      def temp_upload(bytes, name, temps)
        temp = Tempfile.new([ "tracker-upload", File.extname(name).first(20) ], binmode: true)
        temps << temp
        temp.write(bytes)
        temp.flush
        temp.rewind
        type = Marcel::MimeType.for(StringIO.new(bytes.byteslice(0, 4096)), name: name)
        Trackers::UploadFile.new(io: temp, filename: name, content_type: type, size: bytes.bytesize,
                                 sha256: Digest::SHA256.hexdigest(bytes))
      end
    end
  end
end
