# frozen_string_literal: true

# What a suspended session saved, and what Restore puts back (Sessions::Checkpoint,
# Sessions::Restore). One per session; destroyed with the archive when the session
# is restored for good or its restore window closes.
class SessionCheckpoint < ApplicationRecord
  include SessionCheckpointUploader::Attachment(:archive)

  belongs_to :terminal_session

  validates :terminal_session_id, uniqueness: true

  def repos = Array(manifest["repos"])
  def conversation_id = manifest["conversation_id"].presence
  def cli_version = manifest["cli_version"].presence
  def workspace_included? = manifest.dig("workspace", "included") == true
end
