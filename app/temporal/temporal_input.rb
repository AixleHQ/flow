# frozen_string_literal: true

# Workflow and activity inputs arrive as hashes and are read as Hashie::Mash
# (input.session_id, input[:state]). A Mash is a Hash, though: a key named like a
# Hash or Mash method — count, key, zip, size, merge — reads as that method, not
# as its value. No input has such a key; this makes a new one fail on the first
# run instead of quietly reading the wrong thing.
module TemporalInput
  # Nested values are not ours to name: a wrapper's parameters can be called
  # `max`. Hashie logs such a key, and logging inside a workflow is an illegal
  # call, so the workflow task failed on every retry until the run timed out.
  class Mash < Hashie::Mash
    disable_warnings
  end

  SHADOWED = Mash.instance_methods.to_set(&:to_s).freeze

  module_function

  def wrap(input)
    return input unless input.is_a?(Hash)

    shadowing = input.keys.map(&:to_s).select { |key| SHADOWED.include?(key) }
    raise ArgumentError, "input keys shadow Hash methods, rename them: #{shadowing.join(', ')}" if shadowing.any?

    Mash.new(input)
  end
end
