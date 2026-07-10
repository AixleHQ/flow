# frozen_string_literal: true

module InternalTools
  # Platform tool: let a workflow agent send a Slack message. Text and files are
  # both optional, but at least one is required — text only, files only, or both
  # arrive as a SINGLE Slack message. Any number of files can be attached, and
  # each one comes from exactly one source:
  #   - content:   inline text the agent typed out (needs filename)
  #   - file_path: a path inside the running container — ANY file type, including
  #                binary (png, pdf, xlsx, ...) the agent just produced this step
  #   - asset_id:  a stored project asset's latest version bytes (any type)
  # Gated on the project having an active Slack integration. Defaults the
  # channel/thread to the message that triggered the run.
  class SlackPostMessage < Base
    tool do
      display_name "Slack Post Message"
      description "Send a Slack message from this workflow. `text` and `files` are both optional but at least one is required — text only, files only, or both arrive as ONE message. Attach any number of files of any type; each file entry sets EXACTLY ONE source: `content` (inline text, needs `filename`), `file_path` (a path in the running container — any type incl. binary), or `asset_id` (a project asset's bytes). Omit channel/thread to reply in the channel/thread that triggered the run. Requires a Slack integration on the project."
      tags :messaging, :slack
      inject_when :workflow_step_session
      requires_integration :slack
      input_schema({
        type: "object",
        required: [],
        properties: {
          text: {
            type: "string",
            description: "Message text. Optional when files are provided."
          },
          files: {
            type: "array",
            items: {
              type: "object",
              required: [],
              properties: {
                title: {
                  type: "string",
                  description: "Optional display title (defaults to filename)"
                },
                filename: {
                  type: "string",
                  description: "File name, e.g. fizzbuzz.rb. Required with `content`; " \
                               "otherwise defaults to the container basename or asset name."
                },
                content: {
                  type: "string",
                  description: "Inline text content of the file. Source option 1 of 3."
                },
                file_path: {
                  type: "string",
                  description: "Path inside the running container to read bytes from, e.g. " \
                               "/workspace/outputs/chart.png. Any file type, including binary. Source option 2 of 3."
                },
                asset_id: {
                  type: "integer",
                  description: "ID of a project asset whose latest-version bytes to attach (any type). Source option 3 of 3."
                }
              }
            },
            description: "Optional file attachments, sent in the SAME message as the text. Each entry sets exactly one of content/file_path/asset_id."
          },
          channel: {
            type: "string",
            description: "Channel ID. Defaults to the triggering channel for Slack-started runs."
          },
          thread_ts: {
            type: "string",
            description: "Thread timestamp to reply into. Defaults to the triggering thread."
          }
        }
      })
    end

    def execute
      require_workflow_context!

      files, file_error = build_files
      return file_error if file_error
      return error("Provide `text` and/or `files`") if params[:text].blank? && files.empty?

      integration = slack_integration
      return error("Slack is not connected for this project") if integration.nil?

      channel = params[:channel].presence || slack_context["channel"]
      return error("No channel given, and this run was not triggered from Slack") if channel.blank?

      thread_ts = params[:thread_ts].presence || slack_context["thread_ts"]
      sent = Slack::Notifier.post(
        integration: integration, channel: channel,
        text: params[:text].presence, files: files.presence, thread_ts: thread_ts
      )
      sent ? success("Sent to #{channel}") : error("Failed to send to Slack")
    end

    private

    # Resolve every files[] entry into the { filename, content, title } shape
    # Slack::Client.upload_files expects. Returns [resolved_array, error]: on the
    # first unresolvable entry, resolved_array is nil and error is a tool error.
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

    def slack_context
      workflow_run&.shared_context.to_h["slack"] || {}
    end

    # Reply through the SAME workspace that triggered this run (its integration is
    # carried in shared_context), so with several connected workspaces the message
    # goes back to the right one. Falls back to any active install for the company
    # (e.g. a run not started from Slack).
    def slack_integration
      return nil if project.nil?

      scope = Integration.active.where(provider: :slack, company_id: project.company_id)

      if (id = slack_context["integration_id"]).present?
        by_id = scope.find_by(id: id)
        return by_id if by_id
      end

      scope.where("project_id = :pid OR project_id IS NULL", pid: project.id)
        .order(Arel.sql("project_id IS NULL"))
        .first
    end
  end
end
