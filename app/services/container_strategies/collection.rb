# frozen_string_literal: true

module ContainerStrategies
  # What one of a cleanup's collectors gathered: how many items it stored, and the
  # notes for what it could not collect whole (a runner session's file or output
  # over 1 MiB, where the platform's storage cannot sign an upload). A collector
  # returns it; the cleanup combines the results and writes the report.
  Collection = Data.define(:count, :uncollected) do
    def self.none = new(count: 0, uncollected: [])

    def self.of(count, uncollected = []) = new(count: count, uncollected: uncollected)
  end
end
