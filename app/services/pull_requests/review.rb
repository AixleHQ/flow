# frozen_string_literal: true

module PullRequests
  # `verdict` is one of approve, unapprove, request_changes.
  Review = Data.define(:reviewer, :verdict, :submitted_at) do
    include Value
  end
end
