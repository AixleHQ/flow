# frozen_string_literal: true

module PullRequests
  # `status` is one of added, modified, removed, renamed.
  FileChange = Data.define(:path, :old_path, :status, :additions, :deletions) do
    include Value
  end
end
