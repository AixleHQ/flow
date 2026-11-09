# frozen_string_literal: true

module Runners
  # A machine the operator installed `aixle-runner` on. The platform creates,
  # rebuilds and calls nothing (docs/design/agent-runtimes/DESIGN.md §5.1).
  class ManualAdapter < Adapter
    def self.type = "manual"

    def capabilities(_runner)
      Capabilities.new(provisionable: false, rebuildable: false)
    end
  end
end
