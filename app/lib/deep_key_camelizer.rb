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
  NOTHING_PRESERVED = [].freeze
  # Resources camelize their own keys and Inertia's prop transformer walks the same
  # tree again, so most keys arrive already camelized; those are reused as they are
  # instead of being rebuilt key by key on every page.
  ALREADY_CAMEL = /\A[a-z][a-zA-Z0-9]*\z/

  def self.call(obj, preserve: false)
    case obj
    when Hash
      preserved = obj[PRESERVE_MARKER] || NOTHING_PRESERVED

      obj.each_with_object({}) do |(k, v), result|
        next if k == PRESERVE_MARKER

        new_key = preserve ? k : camelize_key(k)
        result[new_key] = call(v, preserve: preserved.include?(new_key))
      end
    when Array
      obj.map { |item| call(item, preserve: preserve) }
    else
      obj
    end
  end

  def self.camelize_key(key)
    name = key.is_a?(Symbol) ? key.name : key.to_s
    name.match?(ALREADY_CAMEL) ? name : name.camelize(:lower)
  end
end
