# frozen_string_literal: true

module PersonalTools
  # The second half of attaching a file to a board task: the bytes a caller
  # PUT to create_task_asset_upload's URL become a task asset, exactly as a
  # file attached in the UI does. Short text skips the upload and arrives in
  # `content`.
  class AttachTaskAsset < Base
    MAX_CONTENT_BYTES = 1.megabyte

    tool do
      display_name "Attach Task Asset"
      description "Attach a file to a board task. Either pass `upload_id` from create_task_asset_upload after " \
                  "PUTting the file's bytes to its upload_url, or pass short text (markdown, a log, JSON — up " \
                  "to 1 MB) as `content` with a `name`. get_board_task lists the task's files afterwards."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
      param :upload_id, type: :string, description: "From create_task_asset_upload, once the bytes are uploaded."
      param :content, type: :string, description: "Text to attach instead of an upload, up to 1 MB."
      param :name, type: :string,
                   description: "The attachment's name, extension included. Required with `content`; " \
                                "defaults to the upload's filename."
      param :tags, type: :array, description: "Optional asset tags.", items: { type: "string" }
    end

    def execute
      project = find_project!
      authorize!(project.board, :create?, policy: Web::Company::Projects::Board::Task::AssetsPolicy, project: project)
      task = project.board&.board_tasks&.find_by(id: params[:task_id])
      return error("Task not found on this project's board") unless task
      return error("Pass either upload_id or content, not both") if params[:upload_id].present? && text?

      file, name = text? ? text_file : uploaded_file(task)
      return file if file.is_a?(Hash)

      asset = TaskService.add_asset(task: task, params: { name: name, file: file, tags: params[:tags] || [] },
                                    actor: user)
      return error("Could not attach #{name}: #{asset.errors.full_messages.to_sentence}") unless asset.persisted?

      success(id: asset.id, task_id: task.id, name: asset.name, content_type: asset.file&.mime_type,
              size: asset.file&.size)
    end

    private

    # Handed to Shrine as cached-file data, the same descriptor the UI sends
    # after a direct upload. Shrine re-reads size and type from the stored
    # bytes rather than trusting either.
    def uploaded_file(task)
      return error("Pass upload_id (from create_task_asset_upload) or content") if params[:upload_id].blank?

      claim = CreateTaskAssetUpload.redeem(params[:upload_id])
      return error("upload_id is invalid or has expired; start again with create_task_asset_upload") unless claim
      return error("upload_id was issued for another task or user") unless redeemable?(claim, task)

      upload = Uploads::CacheUpload.new(claim["cache_id"])
      return error("Nothing has been uploaded for this upload_id yet; PUT the file to its upload_url first") \
        unless upload.uploaded?

      name = params[:name].presence || claim["filename"]
      [ { id: upload.id, storage: "cache", metadata: { filename: name } }.to_json, name ]
    end

    def text? = !params[:content].nil?

    def redeemable?(claim, task)
      claim["task_id"] == task.id && claim["user_id"] == user.id
    end

    def text_file
      name = params[:name].to_s.strip
      return error("name is required with content") if name.empty?

      content = params[:content].to_s
      if content.bytesize > MAX_CONTENT_BYTES
        return error("content is over 1 MB; upload it with create_task_asset_upload instead")
      end

      io = StringIO.new(content)
      # determine_mime_type falls back to the filename for formats with no
      # magic bytes (.md, .txt, .csv), and reads it from here.
      io.define_singleton_method(:original_filename) { name }
      [ io, name ]
    end
  end
end
