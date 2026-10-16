# frozen_string_literal: true

module PullRequests
  # `parent_id` is the comment this one replies to: a reply lands in its thread.
  Comment = Data.define(:id, :parent_id, :author, :body, :file_path, :line, :resolved, :created_at) do
    include Value
  end
end
