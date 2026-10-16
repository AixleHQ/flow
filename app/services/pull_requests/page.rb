# frozen_string_literal: true

module PullRequests
  Page = Data.define(:items, :next_cursor) do
    include Value

    def has_more? = next_cursor.present?
  end
end
