# frozen_string_literal: true

require "shellwords"

module Sessions
  # Takes a suspended session's checkpoint: one archive, built inside the container and
  # put straight into storage over Uploads::ContainerTransfer's URL.
  # Design: docs/design/session-suspend-restore.md §4.
  #
  #   repos/<repository id>/head.bundle    commits on local branches no remote ref has
  #   repos/<repository id>/tracked.patch  staged and unstaged changes, `git diff --binary HEAD`
  #   repos/<repository id>/untracked.tar  untracked files that are not ignored
  #   conversation.tar                     the CLI's conversation files, from its home
  #   workspace.tar                        /workspace, without the paths in #workspace_excludes
  #
  # The archive is not masked: two CLIs keep their conversation in SQLite. It is read
  # only by Sessions::Restore and the expiry sweep.
  class Checkpoint
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
      stdout, stderr, code = @runtime.exec(@container, [ "/bin/bash", "-c", script(url) ],
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
      excludes << ".#{context.delete_prefix('/workspace')}" if context.start_with?("/workspace/")
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

    def script(url)
      <<~BASH
        set -u
        D=$(mktemp -d /tmp/.aixle-checkpoint.XXXXXX) || exit 70
        trap 'rm -rf "$D" "$D.tgz"' EXIT
        g() { git -c safe.directory='*' "$@"; }
        flag() { [ -e "$1" ] && echo 1 || echo 0; }
        repo() {
          key=$1; path=$2; out="$D/repos/$key"
          if [ ! -d "$path/.git" ]; then printf 'REPO\\t%s\\tmissing\\n' "$key"; return; fi
          mkdir -p "$out"; cd "$path" || return
          branch=$(g symbolic-ref -q --short HEAD || true)
          head=$(g rev-parse -q --verify HEAD || true)
          on_remote=false
          if [ -n "$branch" ] && timeout 30 git -c safe.directory='*' ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then on_remote=true; fi
          dirty=false; [ -n "$(g status --porcelain 2>/dev/null)" ] && dirty=true
          g bundle create "$out/head.bundle" --branches --not --remotes >/dev/null 2>&1 || rm -f "$out/head.bundle"
          g diff --binary HEAD > "$out/tracked.patch" 2>/dev/null; [ -s "$out/tracked.patch" ] || rm -f "$out/tracked.patch"
          g ls-files -z --others --exclude-standard > "$out/.untracked" 2>/dev/null
          if [ -s "$out/.untracked" ]; then tar --null -T "$out/.untracked" -cf "$out/untracked.tar" 2>/dev/null || rm -f "$out/untracked.tar"; fi
          rm -f "$out/.untracked"
          printf 'REPO\\t%s\\tok\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$key" "$branch" "$head" "$on_remote" "$dirty" \\
            "$(flag "$out/head.bundle")" "$(flag "$out/tracked.patch")" "$(flag "$out/untracked.tar")"
        }
        mkdir -p "$D/repos"
        #{repositories.map { |id, path| "repo #{Shellwords.escape(id)} #{Shellwords.escape(path)}" }.join("\n")}
        if cd #{Shellwords.escape(@adapter.home_dir)}; then
          printf 'CONVERSATION\\t%s\\n' "$( { #{@adapter.conversation_id_command || 'true'} ; } 2>/dev/null | head -1)"
          existing=""
          for p in #{@adapter.conversation_paths.map { |p| Shellwords.escape(p) }.join(' ')}; do [ -e "$p" ] && existing="$existing $p"; done
          if [ -n "$existing" ]; then tar -cf "$D/conversation.tar" $existing 2>/dev/null; [ $? -le 1 ] || rm -f "$D/conversation.tar"; fi
        fi
        tar -C /workspace -cf "$D/workspace.tar" #{workspace_excludes.map { |e| "--exclude=#{Shellwords.escape(e)}" }.join(' ')} . 2>/dev/null
        [ $? -le 1 ] || rm -f "$D/workspace.tar"
        pack() { rm -f "$D.tgz"; tar -C "$D" -czf "$D.tgz" "$@"; }
        items="repos"; [ -f "$D/conversation.tar" ] && items="$items conversation.tar"
        workspace=0
        if [ -f "$D/workspace.tar" ] && pack $items workspace.tar && [ "$(stat -c %s "$D.tgz")" -le #{MAX_BYTES} ]; then workspace=1; else pack $items; fi
        size=$(stat -c %s "$D.tgz")
        if [ "$size" -gt #{MAX_BYTES} ]; then printf 'TOO_LARGE\\t%s\\n' "$size"; exit 3; fi
        if ! curl -sS --noproxy '*' --fail --max-time #{UPLOAD_TIMEOUT} -X PUT -T "$D.tgz" #{Shellwords.escape(url)} >/dev/null; then
          echo UPLOAD_FAILED; exit 4
        fi
        printf 'ARCHIVE\\t%s\\t%s\\n' "$size" "$workspace"
      BASH
    end
  end
end
