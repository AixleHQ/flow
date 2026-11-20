# frozen_string_literal: true

# The archive a suspended session leaves (Sessions::Checkpoint). It holds the agent's
# conversation and files as they were, unmasked: Cursor and Antigravity keep their
# conversation in SQLite, which masking would corrupt. So it is only ever read back by
# the restore path, and deleted when the session can no longer be restored.
class SessionCheckpointUploader < Shrine
  plugin :activerecord
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers

  Attacher.validate do
    validate_max_size Sessions::Checkpoint::MAX_BYTES + 64.megabytes, message: "is too large"
  end

  def generate_location(io, record: nil, **)
    return super unless record.is_a?(SessionCheckpoint)

    "sessions/#{record.terminal_session_id}/checkpoint/#{super(io).split('/').last}"
  end
end
