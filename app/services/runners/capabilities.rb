# frozen_string_literal: true

module Runners
  # What the platform may ask of a runner (docs/design/agent-runtimes/DESIGN.md
  # §4). Callers branch on these, never on the runner's type. Only the flags
  # something reads are declared; the rest of §4 arrives with its first reader.
  Capabilities = Data.define(:provisionable, :rebuildable)
end
