# frozen_string_literal: true

# Recursively camelizes the keys of a serialized payload (hashes inside arrays
# inside hashes), so a payload reads the same in TypeScript no matter which
# transport carried it: Inertia props, a JSON API response, or a cable broadcast.
#
# A hash may opt its own children out by listing their (already camelized) keys
# under `_preserveKeys` — that is how an opaque value hash (MCP `env`/`headers`,
# where the keys are user data rather than field names) keeps its keys verbatim.
# The marker itself never reaches the client.
module DeepKeyCamelizer
  PRESERVE_MARKER = "_preserveKeys"

  def self.call(obj, preserve: false)
    case obj
    when Hash
      preserved = Set.new(obj[PRESERVE_MARKER] || [])

      obj.each_with_object({}) do |(k, v), result|
        next if k == PRESERVE_MARKER

        new_key = preserve ? k : k.to_s.camelize(:lower)
        skip_children = preserved.include?(new_key)
        result[new_key] = call(v, preserve: skip_children)
      end
    when Array
      obj.map { |item| call(item, preserve: preserve) }
    else
      obj
    end
  end
end
