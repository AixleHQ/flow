# frozen_string_literal: true

module PullRequests
  MergeResult = Data.define(:merged, :already_merged, :pending, :pull_request) do
    include Value
  end
end
