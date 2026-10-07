# frozen_string_literal: true

module PersonalTools
  # The first half of attaching a file to a board task.
  #
  # A model cannot carry a file's bytes in tool arguments: it would have to
  # write them out as tokens, which no screenshot survives. So the caller PUTs
  # the bytes straight to storage and hands back the upload_id this returns to
  # attach_task_asset. The upload_id is signed and names the task, the user and
  # the storage slot, so it cannot be spent on another task or by another user.
  class CreateTaskAssetUpload < Base
    EXPIRES_IN = 1.hour
    PURPOSE = :task_asset_upload

    tool do
      display_name "Create Task Asset Upload"
      description "Start attaching a file (a screenshot, a PDF, any binary) to a board task. Returns an " \
                  "upload_url that is valid for one hour: PUT the file's bytes to it, for example " \
                  "`curl -sS -X PUT -T <path> '<upload_url>'`, then call attach_task_asset with the upload_id. " \
                  "For short text, attach_task_asset's `content` needs no upload."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
      param :filename, type: :string, required: true,
                       description: "The file's name, extension included. It names the attachment and " \
                                    "decides its content type."
    end

    def self.issue(upload:, task:, user:, filename:)
      verifier.generate({ "cache_id" => upload.id, "task_id" => task.id, "user_id" => user.id,
                          "filename" => filename }, expires_in: EXPIRES_IN, purpose: PURPOSE)
    end

    # Nil when the id was not issued here, has been altered, or has expired.
    def self.redeem(upload_id)
      verifier.verified(upload_id.to_s, purpose: PURPOSE)
    end

    def self.verifier = Rails.application.message_verifier(PURPOSE)

    def execute
      project = find_project!
      authorize!(project.board, :create?, policy: Web::Company::Projects::Board::Task::AssetsPolicy, project: project)
      task = project.board&.board_tasks&.find_by(id: params[:task_id])
      return error("Task not found on this project's board") unless task

      filename = params[:filename].to_s.strip
      return error("filename is required") if filename.empty?

      upload = Uploads::CacheUpload.mint(filename: filename)
      success(upload_id: self.class.issue(upload: upload, task: task, user: user, filename: filename),
              upload_url: upload.presigned_put_url || local_upload_url(upload),
              method: "PUT", expires_in_seconds: EXPIRES_IN.to_i, task_id: task.id, filename: filename)
    end

    private

    # Locally the :cache storage cannot sign uploads, and the stand-in that
    # takes them is the one the browser uses — it needs a signed-in session.
    # Built by hand: url_for(host: Settings.domain) drops a port the domain
    # carries.
    def local_upload_url(upload)
      path = Rails.application.routes.url_helpers.upload_api_v1_assets_path(key: upload.key)
      "#{Settings.protocol}://#{Settings.domain}#{path}"
    end
  end
end
