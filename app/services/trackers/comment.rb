# frozen_string_literal: true

module Trackers
  Comment = Data.define(:id, :issue_id, :author, :body, :created_at) do
    include Value
  end
end
