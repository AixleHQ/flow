# frozen_string_literal: true

module PullRequests
  # `number` is what a person sees: GitLab's iid, Bitbucket's id. `state` is one of
  # open, merged, closed; `mergeable` is nil while the host has not decided.
  PullRequest = Data.define(:number, :url, :title, :description, :state, :draft, :source_branch, :target_branch,
                            :head_sha, :author, :reviewers, :mergeable, :created_at, :updated_at) do
    include Value

    def open? = state == "open"
    def merged? = state == "merged"
  end
end
