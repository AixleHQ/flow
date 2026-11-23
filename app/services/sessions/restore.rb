# frozen_string_literal: true

require "base64"
require "shellwords"

module Sessions
  # Puts a suspended session's checkpoint back into the session that continues it, with
  # restore.sh, after the usual provisioning and before the CLI starts. Design:
  # docs/design/session-suspend-restore.md §5.
  #
  # Nothing here fails the session: whatever cannot be put back is left in
  # /workspace/.aixle-restore and named in the restore notice, and a conversation that
  # cannot be resumed starts fresh.
  class Restore
    SCRIPT = File.read(File.expand_path("restore.sh", __dir__)).freeze
    METADATA_KEY = "restore"
    LEFTOVERS_DIR = "/workspace/.aixle-restore"
    SCRIPT_TIMEOUT = 25.minutes.to_i
    DOWNLOAD_TIMEOUT = 20.minutes.to_i
    RESOURCES = {
      tool_ids: :tools, skill_ids: :skills, mcp_server_ids: :mcp_servers, input_asset_ids: :input_assets,
      repository_ids: :repositories, config_item_ids: :config_items
    }.freeze

    # The new session's configuration: the suspended one's, without what has since gone.
    def self.params_for(session)
      notes = []
      resources = RESOURCES.to_h do |param, association|
        kept, gone = session.public_send(association).partition { |record| available?(record) }
        gone.each { |record| notes << "#{record.class.model_name.human} \"#{record.try(:name) || record.id}\" is no longer available" }
        [ param, kept.map(&:id) ]
      end

      metadata = session.metadata.to_h.slice("aixle_builder")
      metadata[METADATA_KEY] = { "notes" => notes } if notes.any?
      {
        mode: "interactive", requested_model: session.requested_model, reasoning_effort: session.reasoning_effort,
        session_config: session.session_config, runner_id: session.runner_id,
        restored_from_session_id: session.id, metadata: metadata
      }.merge(resources).compact
    end

    def self.available?(record)
      return false if record.respond_to?(:archived_at) && record.archived_at.present?
      return false if record.respond_to?(:deleted_at) && record.deleted_at.present?

      true
    end

    def initialize(session:, container:, runtime:, adapter:)
      @session = session
      @container = container
      @runtime = runtime
      @adapter = adapter
    end

    # → the state recorded under metadata["restore"], which #launch reads
    def call
      checkpoint = @session.restored_from_session&.session_checkpoint
      return record!(resume: false, notes: [ "The saved files were no longer available, so nothing was restored." ]) unless checkpoint

      url = Uploads::ContainerTransfer.get_url(checkpoint.archive, expires_in: 1.hour.to_i,
                                                                   host: @runtime.callback_url(:container_assets, @session))
      return record!(resume: false, notes: [ "The saved files could not be fetched, so nothing was restored." ]) if url.blank?

      stdout, stderr, code = @runtime.exec(@container, [ "/bin/bash", "-c", SCRIPT, "aixle-restore", *arguments(url, checkpoint) ],
                                           stdout: true, stderr: true, timeout: SCRIPT_TIMEOUT + 60)
      lines = Array(stdout).join.lines.map { |line| line.chomp.split("\t", -1) }
      unless code.to_i.zero?
        Rails.logger.warn("[Restore] session=#{@session.id} restore script exited #{code}: #{Array(stderr).join.strip.truncate(300)}")
        return record!(resume: false, notes: [ "The saved files could not be unpacked (#{lines.flatten.first || "exit #{code}"}), so nothing was restored." ])
      end

      conversation = lines.any? { |fields| fields.first == "CONVERSATION_OK" }
      record!(resume: resume?(checkpoint, conversation), conversation_id: checkpoint.conversation_id,
              notes: notes_for(checkpoint, lines, conversation))
    end

    # The command the CLI starts with: the resumed conversation, or a fresh one.
    def self.launch_command(session, adapter, mode:, model:, effort:)
      state = session.metadata.to_h[METADATA_KEY].to_h
      resumed = adapter.resume_command(state["conversation_id"], mode: mode, model: model, effort: effort) if state["resume"]
      resumed || adapter.session_command(mode: mode, model: model, effort: effort)
    end

    private

    def resume?(checkpoint, conversation)
      conversation && checkpoint.conversation_id.present? && @adapter.resumable? &&
        checkpoint.cli_version.present? && checkpoint.cli_version == current_cli_version
    end

    def current_cli_version
      AgentRuntime.fetch(@session.agent_type).cli_version
    rescue StandardError
      nil
    end

    def notes_for(checkpoint, lines, conversation)
      notes = Array(@session.metadata.to_h.dig(METADATA_KEY, "notes"))
      notes << "Files under /workspace other than the repositories were not saved: the archive was too large." unless checkpoint.workspace_included?
      if conversation && !resume?(checkpoint, conversation)
        notes << "The earlier conversation could not be resumed#{" (the agent CLI changed from #{checkpoint.cli_version} to #{current_cli_version})" if checkpoint.cli_version != current_cli_version}. " \
                 "Its files are in #{@adapter.home_dir} as the CLI keeps them (#{@adapter.conversation_paths.join(', ')})."
      end
      notes << "The earlier conversation was not saved." unless conversation
      lines.select { |fields| fields.first == "REPO" && fields[2] != "ok" }.each do |_tag, id, status|
        path = checkpoint.repos.find { |repo| repo["repository_id"].to_s == id }&.dig("path") || "repository #{id}"
        notes << repo_note(path, status, id)
      end
      notes.compact
    end

    def repo_note(path, status, id)
      case status
      when "missing" then "#{path} was not cloned for this session, so its saved work was not put back."
      when "bundle_failed" then "Unpushed commits of #{path} could not be put back; they are in #{LEFTOVERS_DIR}/#{id}.bundle."
      when "patch_failed" then "Uncommitted changes of #{path} could not be applied; they are in #{LEFTOVERS_DIR}/#{id}.patch."
      when "head_missing" then "The commit #{path} was on could not be found; it is left on its branch."
      when "untracked_failed" then "Untracked files of #{path} could not all be put back."
      end
    end

    def record!(resume:, notes:, conversation_id: nil)
      state = { "resume" => resume, "conversation_id" => conversation_id, "notes" => notes }.compact
      @session.change_jsonb!(:metadata) { |doc| doc[METADATA_KEY] = state }
      append_notice(notes)
      state
    end

    def append_notice(notes)
      path = @adapter.context_file_path
      return if path.blank?

      origin = @session.restored_from_session
      text = +"\n\n## This session was restored\n\n"
      text << "It continues session ##{origin&.id}, suspended #{origin&.suspended_at&.utc&.strftime('%Y-%m-%d %H:%M UTC')}. "
      text << "The files under /workspace and the repositories' branches and changes were put back. "
      text << "Processes that were running are gone, and anything installed or written outside /workspace "
      text << "(global packages, caches, /tmp) was not kept: install dependencies again before relying on them.\n"
      notes.each { |note| text << "\n- #{note}" }
      encoded = Base64.strict_encode64(text)
      @runtime.exec(@container, [ "/bin/sh", "-c", "echo #{encoded} | base64 -d >> #{Shellwords.escape(path)}" ])
    rescue StandardError => e
      Rails.logger.warn("[Restore] session=#{@session.id} could not write the restore notice: #{e.message}")
    end

    def arguments(url, checkpoint)
      [
        "--url", url, "--download-timeout", DOWNLOAD_TIMEOUT,
        "--workspace", Checkpoint::WORKSPACE, "--home", @adapter.home_dir, "--leftovers", LEFTOVERS_DIR,
        *checkpoint.repos.flat_map do |repo|
          [ "--repo", repo["repository_id"], repo["path"], repo["branch"], repo["head_sha"], repo["on_remote"] ]
        end
      ].map(&:to_s)
    end
  end
end
