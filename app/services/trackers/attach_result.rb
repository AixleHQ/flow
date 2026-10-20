# frozen_string_literal: true

module Trackers
  # What attaching files did: the files now on the issue, the comment that shows
  # them when one was posted, and what happened to each file sent.
  AttachResult = Data.define(:attachments, :comment, :issue_id, :files) do
    include Value

    def id = comment&.id || attachments.first&.id
  end
end
