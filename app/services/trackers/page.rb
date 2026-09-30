# frozen_string_literal: true

module Trackers
  # One page of a list. `next_cursor` is opaque to callers and nil on the last page.
  Page = Data.define(:items, :next_cursor) do
    include Value

    def has_more? = next_cursor.present?
  end
end
