# frozen_string_literal: true

module Trackers
  # Bytes on their way to an issue: an open IO positioned at its start.
  UploadFile = Data.define(:io, :filename, :content_type, :size, :sha256) do
    def image?
      content_type.to_s.start_with?("image/")
    end
  end
end
