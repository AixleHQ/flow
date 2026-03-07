# frozen_string_literal: true

module InternalTools
  class BoardAttachAsset < Base
    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      decoded = Base64.decode64(params[:file_content])

      author = resolve_actor(task)
      return error("Cannot determine asset author") unless author

      filename = params[:name]
      io = StringIO.new(decoded)
      io.define_singleton_method(:original_filename) { filename }
      uploaded_file = TaskAssetUploader.upload(io, :store)

      asset = task.task_assets.create!(
        name: params[:name],
        author: author,
        author_type: :agent,
        tags: params[:tags] || [],
        file_data: uploaded_file.to_json
      )

      BoardChannel.broadcast_event(board, "task_changed", {
        action: "updated",
        task: BoardTaskSerializer.new(task.reload).serializable_hash
      })

      success({ id: asset.id, name: asset.name }.to_json)
    end

    private

    def resolve_actor(task)
      task.assignee || workflow_run&.user
    end
  end
end
