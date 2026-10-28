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

  # Marks every hash in `obj` so the whole tree keeps its keys verbatim, at any
  # depth. A marker covers only its own hash's children, so data whose keys are
  # names at every level (a runner's config, a JSON Schema) needs one per hash.
  def self.verbatim(obj)
    case obj
    when Hash
      obj.to_h { |k, v| [ k.to_s, verbatim(v) ] }.merge(PRESERVE_MARKER => obj.keys.map(&:to_s))
    when Array
      obj.map { |item| verbatim(item) }
    else
      obj
    end
  end

  def self.camelize_key(key)
    name = key.is_a?(Symbol) ? key.name : key.to_s
    name.match?(ALREADY_CAMEL) ? name : name.camelize(:lower)
  end
end
