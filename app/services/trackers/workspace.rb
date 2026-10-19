# frozen_string_literal: true

module Trackers
  # Where an issue's files land in an agent's container:
  # /workspace/tracker/<issue key>/<file name> (docs/design/tracker-attachments.md §5.1).
  class Workspace
    ROOT = "/workspace/tracker"
    MAX_NAME = 150

    # A file name safe to keep on a card and in a container: no directories, no
    # control characters, no leading dots, at most MAX_NAME characters with its
    # extension kept.
    def self.clean_name(name)
      base = File.basename(name.to_s.tr("\\", "/")).gsub(/[[:cntrl:]]/, "").strip.sub(/\A\.+/, "")
      return "file" if base.blank?
      return base if base.length <= MAX_NAME

      ext = File.extname(base).first(20)
      "#{base.delete_suffix(File.extname(base)).first(MAX_NAME - ext.length)}#{ext}"
    end

    def self.folder(issue_key)
      issue_key.to_s.gsub(/[^A-Za-z0-9._-]+/, "-").delete_prefix("-").delete_suffix("-").presence || "issue"
    end

    def self.path_for(issue_key, name)
      SafeRelativePath.join(ROOT, "#{folder(issue_key)}/#{clean_name(name)}")
    end

    def self.for_session(session)
      return if session&.container_id.blank?

      uid = AgentCredentialsService.for(session.agent_type).adapter.container_uid
      new(runtime: ContainerRuntime.build, container: session.container_id, uid: uid)
    end

    def initialize(runtime:, container:, uid:)
      @runtime = runtime
      @container = container
      @uid = uid
    end

    # A stored file, fetched by the container itself so the bytes never pass
    # through this process. Names are free-form, so every part is escaped.
    def fetch(url, path)
      dir = Shellwords.escape(File.dirname(path))
      target = Shellwords.escape(path)
      source = Shellwords.escape(ContainerAssetUrl.call(url, host: Settings.container_asset_host))
      _out, _err, code = @runtime.exec(@container, [ "sh", "-c",
                                                     "mkdir -p #{dir} && curl -fsSL -o #{target} #{source} && chown -R #{@uid}:#{@uid} #{Shellwords.escape(ROOT)}" ])
      code.to_i.zero?
    end

    def write(path, bytes)
      @runtime.write_file(@container, path, bytes, uid: @uid, gid: @uid)
    end
  end
end
