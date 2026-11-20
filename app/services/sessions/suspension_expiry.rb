# frozen_string_literal: true

require "rubygems/package"
require "zlib"

module Sessions
  # The end of a suspended session's restore window (docs/design/session-suspend-restore.md
  # §6). Its outputs come out of the checkpoint as assets, as a finished session's would
  # have; then the archive is deleted and the session is finished. A restored session's
  # archive is kept until the same date, so a failed restore can be tried again, and
  # deleted then.
  class SuspensionExpiry
    OUTPUTS_PREFIX = "./outputs/"

    def self.remind_due(now: Time.current)
      TerminalSession.suspended
                     .where(restore_expires_at: now..(now + Suspension::REMINDER_BEFORE))
                     .where("terminal_sessions.metadata->>'#{Suspension::REMINDED_KEY}' IS NULL")
                     .find_each.count do |session|
        session.change_jsonb!(:metadata) { |doc| doc[Suspension::REMINDED_KEY] = now.utc.iso8601 }
        SessionMailer.restore_expiring(session.id).deliver_later
      end
    end

    def self.expire_due(now: Time.current)
      expired = TerminalSession.suspended.where(restore_expires_at: ...now).find_each.count { |session| new(session).expire! }
      TerminalSession.where(state: "restored", restore_expires_at: ...now).joins(:session_checkpoint)
                     .find_each { |session| session.session_checkpoint.destroy! }
      expired
    end

    def initialize(session)
      @session = session
    end

    def expire!
      checkpoint = @session.session_checkpoint
      import_outputs(checkpoint) if checkpoint
      checkpoint&.destroy!
      @session.change_jsonb!(:metadata) { |doc| doc[Suspension::EXPIRED_KEY] = true }
      @session.expire_suspension!
      true
    rescue StandardError => e
      Rails.logger.error("[SuspensionExpiry] session=#{@session.id}: #{e.class}: #{e.message}")
      false
    end

    private

    # The archive's workspace.tar sits inside a gzipped tar; it is spooled to disk because
    # the inner tar has to be read from the start, and it can be large.
    def import_outputs(checkpoint)
      return unless checkpoint.workspace_included?

      Tempfile.create([ "checkpoint-workspace", ".tar" ], binmode: true) do |workspace|
        next unless spool_workspace(checkpoint, workspace)

        workspace.rewind
        Gem::Package::TarReader.new(workspace) do |inner|
          inner.each do |file|
            next unless file.file? && file.full_name.start_with?(OUTPUTS_PREFIX)

            relative = file.full_name.delete_prefix(OUTPUTS_PREFIX)
            content = file.read.to_s
            next if relative.blank? || content.empty?

            OutputAssets.create!(@session, relative, StringIO.new(content))
          end
        end
      end
    end

    # → whether the archive held a workspace.tar
    def spool_workspace(checkpoint, workspace)
      found = false
      checkpoint.archive.open do |io|
        Gem::Package::TarReader.new(Zlib::GzipReader.new(io)) do |outer|
          entry = outer.find { |e| e.full_name.delete_prefix("./") == "workspace.tar" }
          next unless entry

          IO.copy_stream(entry, workspace)
          found = true
        end
      end
      found
    end
  end
end
