# frozen_string_literal: true

module PersonalTools
  # Reads a text file the platform holds: a workflow run's output, a file
  # attached to a board task, or a project asset. The run and task views list
  # these files by id; this is how a caller gets at what is inside them without
  # a signed URL or the REST API.
  class ReadAsset < Base
    SOURCES = %w[run task project].freeze
    DEFAULT_LIMIT = 50_000
    MAX_LIMIT = 200_000
    TEXT_TYPES = %r{\A(text/|application/(json|x?yaml|xml|javascript|x-sh|x-ndjson|sql|toml))}

    tool do
      display_name "Read Asset"
      description "Read a text file the platform holds: an output a workflow run wrote to /workspace/outputs " \
                  "(source \"run\", with run_id; get_workflow_run lists them), a file attached to a board task " \
                  "(source \"task\", with task_id; get_board_task lists them), or a project asset (source " \
                  "\"project\"; list_assets lists them). Returns up to `limit` bytes from `offset`; follow " \
                  "next_offset to page through a large file. Binary files are refused with their size and type."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :source, type: :string, enum: SOURCES, required: true,
                     description: "Where the file lives: run, task or project."
      param :asset_id, type: :integer, required: true,
                       description: "The file's id, as the run, task or asset listing shows it."
      param :run_id, type: :integer, description: "Workflow run id (source run)."
      param :task_id, type: :integer, description: "Board task id (source task)."
      param :offset, type: :integer, description: "Byte offset to start reading at (default 0)."
      param :limit, type: :integer,
                    description: "Bytes to return (default #{DEFAULT_LIMIT}, at most #{MAX_LIMIT})."
    end

    def execute
      project = find_project!
      return error("source must be one of: #{SOURCES.join(', ')}") unless SOURCES.include?(params[:source])
      return error("run_id is required for source run") if params[:source] == "run" && params[:run_id].blank?
      return error("task_id is required for source task") if params[:source] == "task" && params[:task_id].blank?

      record = find_record(project)
      return error("#{params[:source].capitalize} file #{params[:asset_id]} not found") unless record

      file = file_of(record)
      return error("#{record.name} has no stored file") unless file

      read(record, file)
    end

    private

    def find_record(project)
      case params[:source]
      when "run"
        authorize!(project, :show?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)
        WorkflowRun.where(project: project).find_by(id: params[:run_id])&.workflow_run_assets&.find_by(id: params[:asset_id])
      when "task"
        return nil unless project.board

        authorize!(project.board, :show?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
        project.board&.board_tasks&.find_by(id: params[:task_id])&.task_assets&.find_by(id: params[:asset_id])
      when "project"
        authorize!(project, :index?, policy: Web::Company::Projects::AssetsPolicy, project: project)
        Asset.accessible_from_project(project).find_by(id: params[:asset_id])
      end
    end

    def file_of(record)
      record.is_a?(Asset) ? record.latest_version&.file : record.file
    end

    def read(record, file)
      size = file.size.to_i
      type = file.mime_type.to_s
      offset = [ params[:offset].to_i, 0 ].max
      limit = params[:limit].to_i.positive? ? [ params[:limit].to_i, MAX_LIMIT ].min : DEFAULT_LIMIT

      chunk = read_range(file, offset, limit)
      text = whole_characters(chunk)
      return error("#{record.name} is binary (#{type.presence || 'unknown type'}, #{size} bytes)") unless text?(type, text)

      next_offset = offset + text.bytesize
      success(name: record.name, content_type: type.presence, size: size, offset: offset,
              next_offset: next_offset < size ? next_offset : nil, content: text)
    end

    # Seek when the storage IO allows it, so a large output is not pulled whole
    # for one page; otherwise read and slice.
    def read_range(file, offset, limit)
      file.open do |io|
        io.seek(offset) if offset.positive?
        io.read(limit).to_s
      end
    rescue StandardError
      file.read.to_s.byteslice(offset, limit).to_s
    end

    # A page boundary can split a multi-byte character; hand back only whole
    # ones and let next_offset resume at the cut.
    def whole_characters(chunk)
      text = chunk.dup.force_encoding(Encoding::UTF_8)
      3.times do
        break if text.valid_encoding? || text.empty?

        text = text.byteslice(0, text.bytesize - 1)
      end
      text
    end

    def text?(type, text)
      return false unless text.valid_encoding?
      return true if type.match?(TEXT_TYPES)

      !text.include?("\u0000")
    end
  end
end
