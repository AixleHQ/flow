# frozen_string_literal: true

module Sessions
  # Takes a suspended session's checkpoint: one archive, built inside the container by
  # checkpoint.sh and put straight into storage over Uploads::ContainerTransfer's URL.
  # Design: docs/design/session-suspend-restore.md §4.
  #
  #   repos/<repository id>/head.bundle    commits on local branches and HEAD that no remote ref has
  #   repos/<repository id>/tracked.patch  staged and unstaged changes, `git diff --binary HEAD`
  #   repos/<repository id>/untracked.tar  untracked files that are not ignored
  #   conversation.tar                     the CLI's conversation files, from its home
  #   workspace.tar                        /workspace, without the paths in #workspace_excludes
  #
  # The archive is not masked: two CLIs keep their conversation in SQLite. It is read
  # only by Sessions::Restore and the expiry sweep.
  class Checkpoint
    SCRIPT = File.read(File.expand_path("checkpoint.sh", __dir__)).freeze
    WORKSPACE = "/workspace"
    MAX_BYTES = 2.gigabytes
    SCRIPT_TIMEOUT = 25.minutes.to_i
    UPLOAD_TIMEOUT = 20.minutes.to_i
    CLEANUP_TIMEOUT = SCRIPT_TIMEOUT + 10.minutes.to_i
    # Rebuildable, and usually most of the bytes. Matched at any depth.
    REBUILDABLE_DIRS = %w[node_modules .venv venv __pycache__ .next .turbo .cache .gradle target dist build].freeze
    # Provisioned again for the new session, or restored on their own.
    PROVISIONED_PATHS = %w[./repo ./assets ./.mcp.json ./.aixle ./_bmad].freeze

    class Failed < StandardError; end

    def initialize(session:, container:, runtime:, adapter:)
      @session = session
      @container = container
      @runtime = runtime
      @adapter = adapter
    end

    def call
      key = "#{SecureRandom.hex(30)}.tar.gz"
      # Signed before the archive is built, so it has to outlive the whole script.
      url = Uploads::ContainerTransfer.put_url(SessionCheckpointUploader, :cache, key, expires_in: SCRIPT_TIMEOUT + 300,
                                                                                    host: @runtime.callback_url(:container_assets, @session))
      stdout, stderr, code = @runtime.exec(@container, [ "/bin/bash", "-c", SCRIPT, "aixle-checkpoint", *arguments(url) ],
                                           stdout: true, stderr: true, timeout: SCRIPT_TIMEOUT + 60)
      lines = Array(stdout).join.lines.map { |line| line.chomp.split("\t", -1) }
      archive = lines.find { |fields| fields.first == "ARCHIVE" }
      raise Failed, failure_message(lines, stderr, code) unless code.to_i.zero? && archive

      bytes = archive[1].to_i
      file = SessionCheckpointUploader.uploaded_file(
        id: key, storage: :cache,
        metadata: { "filename" => "checkpoint.tar.gz", "size" => bytes, "mime_type" => "application/gzip" }
      )
      # As data, not as the file: Shrine uploads an assigned file object into the cache
      # again before it promotes it, a second copy of up to 2 GB.
      SessionCheckpoint.create!(terminal_session: @session, archive: file.to_json, byte_size: bytes,
                                manifest: manifest(lines, bytes, workspace: archive[2] == "1"))
    end

    def workspace_excludes
      excludes = PROVISIONED_PATHS.dup
      context = @adapter.context_file_path.to_s
      excludes << ".#{context.delete_prefix(WORKSPACE)}" if context.start_with?("#{WORKSPACE}/")
      excludes + REBUILDABLE_DIRS
    end

    private

    def repositories
      RepositoryWorkspacePath.stored_map(@session).map { |id, path| [ id.to_s, path.to_s ] }
                                                 .select { |_id, path| path.start_with?(RepositoryWorkspacePath::ROOT) }
    end

    def manifest(lines, bytes, workspace:)
      {
        "version" => 1,
        "agent_type" => @session.agent_type,
        "cli_version" => cli_version,
        "conversation_id" => lines.find { |fields| fields.first == "CONVERSATION" }&.dig(1).presence,
        "reason" => Suspension.reason(@session),
        "repos" => lines.select { |fields| fields.first == "REPO" && fields[2] == "ok" }.map { |fields| repo_entry(fields) },
        "missing_repos" => lines.select { |fields| fields.first == "REPO" && fields[2] != "ok" }.map { |fields| fields[1] },
        "workspace" => { "included" => workspace, "excluded" => workspace_excludes },
        "bytes" => bytes
      }
    end

    def repo_entry(fields)
      _tag, id, _ok, branch, head, on_remote, dirty, bundle, patch, untracked = fields
      {
        "repository_id" => id.to_i, "path" => repositories.to_h[id], "branch" => branch.presence, "head_sha" => head.presence,
        "on_remote" => on_remote == "true", "dirty" => dirty == "true",
        "bundle" => bundle == "1", "patch" => patch == "1", "untracked" => untracked == "1"
      }
    end

    def cli_version
      AgentRuntime.fetch(@session.agent_type).cli_version
    rescue StandardError
      nil
    end

    def failure_message(lines, stderr, code)
      reason = lines.find { |fields| %w[TOO_LARGE UPLOAD_FAILED].include?(fields.first) }&.join(" ")
      "checkpoint script exited #{code}#{": #{reason}" if reason}#{": #{Array(stderr).join.strip.truncate(300)}" if reason.nil? && stderr.present?}"
    end

    def arguments(url)
      [
        "--url", url, "--max-bytes", MAX_BYTES, "--upload-timeout", UPLOAD_TIMEOUT,
        "--workspace", WORKSPACE, "--home", @adapter.home_dir,
        "--conversation-id-command", @adapter.conversation_id_command || "true",
        *@adapter.conversation_paths.flat_map { |path| [ "--conversation", path ] },
        *repositories.flat_map { |id, path| [ "--repo", id, path ] },
        *workspace_excludes.flat_map { |pattern| [ "--exclude", pattern ] }
      ].map(&:to_s)
    end
  end
end
