# frozen_string_literal: true

module PullRequests
  # `state` is pending, passed, failed, or none when no CI reported anything for
  # the head commit. Items are {name, status, url}, status pending, passed or failed.
  # `pipeline` is the pull request's head pipeline as {id, status, url} on hosts
  # whose CI gate is keyed by a pipeline id (GitLab), nil elsewhere.
  Checks = Data.define(:state, :head_sha, :items, :pipeline) do
    include Value

    def initialize(state:, head_sha:, items:, pipeline: nil) = super
  end
end
