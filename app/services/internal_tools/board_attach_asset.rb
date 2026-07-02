# frozen_string_literal: true

module InternalTools
  class BoardAttachAsset < Base
    tool do
      display_name "Board Attach Asset"
      description "Attach a file to a board task by reading it from a path inside the running container."
      tags :board
      inject_when :workflow_step_session
      input_schema({
        type: "object",
        required: %w[task_id name file_path],
        properties: {
          name: {
            type: "string",
            description: "Attachment filename"
          },
          tags: {
            type: "array",
            items: {
              type: "string"
            },
            description: "Optional asset tags"
          },
          task_id: {
            type: "integer",
            description: "Board task ID"
          },
          file_path: {
            type: "string",
            description: "Path inside the running container to upload"
          }
        }
      })
    end

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      file_data = resolve_file_data
      return file_data if file_data.is_a?(Hash) && file_data[:exit_code]

      author = resolve_actor(task)
      return error("Cannot determine asset author") unless author

      filename = params[:name]
      io = StringIO.new(file_data)
      io.define_singleton_method(:original_filename) { filename }
      uploaded_file = TaskAssetUploader.upload(io, :store)

      asset = task.task_assets.create!(
        name: params[:name],
        author: author,
        author_type: :agent,
        tags: params[:tags] || [],
        file_data: uploaded_file.to_json
      )

      board.touch

      success({ id: asset.id, name: asset.name }.to_json)
    end

    private

    def resolve_file_data
      if params[:file_path].present?
        read_file_from_container(params[:file_path])
      else
        error("file_path is required")
      end
    end

    def read_file_from_container(path)
      container_id = session.container_id
      return error("No container available to read file from") unless container_id.present?

      content = ContainerRuntime.build.read_file(container_id, path)
      return error("File not found in container: #{path}") unless content

      content
    end

    def resolve_actor(task)
      task.assignee || workflow_run&.user
    end
  end
end
