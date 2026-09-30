# frozen_string_literal: true

module Trackers
  # `category` is the portable part — todo, in_progress, done or canceled — and
  # nil when the tracker does not say.
  Status = Data.define(:id, :name, :category) do
    include Value
  end
end
