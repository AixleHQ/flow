# frozen_string_literal: true

module PullRequests
  # `state` is pending, passed, failed, or none when no CI reported anything for
  # the head commit. Items are {name, status, url}, status pending, passed or failed.
  Checks = Data.define(:state, :head_sha, :items) do
    include Value
  end
end
