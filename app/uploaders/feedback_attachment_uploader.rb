# frozen_string_literal: true

class FeedbackAttachmentUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :validation_helpers

  # No MIME allowlist, as for task assets: the file is only ever opened as a copy
  # on a board card, from the isolated S3 bucket origin (TaskAssetUploader).
  Attacher.validate do
    validate_max_size FeedbackAttachment::MAX_SIZE, message: "is too large (max is #{FeedbackAttachment::MAX_SIZE / 1.megabyte} MB)"
  end
end
