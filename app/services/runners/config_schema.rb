# frozen_string_literal: true

module Runners
  # The `runners.config` keys of docs/design/agent-runtimes/DESIGN.md §2.7, held
  # as data: each key's JSON Schema, its default, the runner types it applies
  # to, and whether it arrives later. It produces the per-type JSON Schema the
  # runner form renders from, and it is what `Runner` validates `config` with.
  #
  # Defaults live here and are never written into `config` (§2.7): `value`
  # applies them at read time, so a later change of a default reaches every
  # runner that does not set the key.
  module ConfigSchema
    Key = Data.define(:path, :types, :schema, :default, :required, :later) do
      def applies_to?(type) = types.include?(type.to_s)
      def property_schema = default.nil? ? schema : schema.merge("default" => default)
    end

    ALL = %w[manual coder kubernetes].freeze
    MACHINE = %w[manual coder].freeze
    ABSOLUTE_PATH = { "type" => "string", "pattern" => "\\A/" }.freeze
    UUID = { "type" => "string", "format" => "uuid" }.freeze

    def self.key(path, types:, schema:, default: nil, required: false, later: false)
      Key.new(path: path, types: types, schema: schema, default: default, required: required, later: later)
    end
    private_class_method :key

    KEYS = [
      key("template_id", types: %w[coder], required: true, schema: UUID),
      key("template_version_policy", types: %w[coder], default: "active", schema: { "enum" => %w[active pinned] }),
      key("template_version_id", types: %w[coder], schema: UUID),
      key("parameters", types: %w[coder], default: {},
                        schema: { "type" => "object", "additionalProperties" => { "type" => "string" } }),
      key("on_release", types: %w[coder], default: "delete", schema: { "enum" => %w[delete stop] }),
      key("namespace", types: %w[kubernetes], required: true,
                       schema: { "type" => "string", "maxLength" => 63, "pattern" => "\\A[a-z0-9]([-a-z0-9]*[a-z0-9])?\\z" }),
      key("reconnect_grace", types: ALL, default: 900, schema: { "type" => "integer", "minimum" => 60, "maximum" => 7200 }),
      key("auto_update", types: %w[manual], default: true, schema: { "type" => "boolean" }),
      key("container.image_override", types: ALL, schema: { "type" => "string", "minLength" => 1 }),
      key("container.resources", types: ALL, schema: {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "cpus" => { "type" => "number", "exclusiveMinimum" => 0 },
          "memory" => { "type" => "string", "pattern" => "\\A[0-9]+(\\.[0-9]+)?([kKmMgGtT]i?)?\\z" }
        }
      }),
      key("container.workspace_volume", types: MACHINE, default: true, schema: { "type" => "boolean" }),
      key("container.cache_mounts", types: MACHINE, default: [], schema: {
        "type" => "array",
        "items" => {
          "type" => "object",
          "additionalProperties" => false,
          "required" => %w[target],
          "properties" => {
            "name" => { "type" => "string", "pattern" => "\\A[a-z0-9][a-z0-9_.-]*\\z" },
            "host_path" => ABSOLUTE_PATH,
            "target" => ABSOLUTE_PATH
          },
          "oneOf" => [ { "required" => %w[name] }, { "required" => %w[host_path] } ]
        }
      }),
      key("container.home_mount", types: MACHINE, schema: {
        "type" => %w[object null],
        "additionalProperties" => false,
        "properties" => { "path" => ABSOLUTE_PATH, "writable" => { "type" => "boolean", "default" => false } }
      }),
      key("container.extra_mounts", types: MACHINE, default: [], schema: {
        "type" => "array",
        "items" => {
          "type" => "object",
          "additionalProperties" => false,
          "required" => %w[source target],
          "properties" => {
            "source" => ABSOLUTE_PATH,
            "target" => ABSOLUTE_PATH,
            "writable" => { "type" => "boolean", "default" => false }
          }
        }
      }),
      key("container.acknowledged_writable_mounts", types: %w[manual], default: [],
                                                    schema: { "type" => "array", "items" => ABSOLUTE_PATH }),
      key("container.network", types: MACHINE, default: "bridge", schema: { "enum" => %w[bridge host] }),
      key("container.pid", types: MACHINE, default: "private", schema: { "enum" => %w[private host] }),
      key("container.allow_privileged_mounts", types: MACHINE, default: false, schema: { "type" => "boolean" }),
      key("container.docker_socket", types: MACHINE, default: false, schema: { "type" => "boolean" }),
      key("execution_mode", types: MACHINE, later: true, default: "container", schema: { "enum" => %w[container host] }),
      key("host.cli_source", types: MACHINE, later: true, default: "managed", schema: { "enum" => %w[managed template] })
    ].index_by(&:path).freeze

    # Top-level keys that only group others (`container.network` is
    # `{"container" => {"network" => ...}}`).
    GROUPS = KEYS.keys.filter_map { |path| path.split(".").first if path.include?(".") }.uniq.freeze

    EPHEMERAL = "ephemeral is not a config key: it is set per machine at registration"
    TYPE_NAMES = { "string" => "a string", "integer" => "an integer", "number" => "a number", "boolean" => "true or false",
                   "object" => "an object", "array" => "a list", "null" => "null" }.freeze

    class << self
      def types = ALL

      # The JSON Schema of one type's `config`: what the form renders and what
      # `errors` checks values against.
      def for_type(type)
        keys = KEYS.values.select { |k| k.applies_to?(type) && !k.later }
        object(keys.reject { |k| k.path.include?(".") }).tap do |schema|
          GROUPS.each do |group|
            nested = keys.select { |k| k.path.start_with?("#{group}.") }
            next if nested.empty?

            schema["properties"][group] = object(nested, prefix: "#{group}.")
          end
          if type.to_s == "coder"
            schema["if"] = { "required" => %w[template_version_policy],
                             "properties" => { "template_version_policy" => { "const" => "pinned" } } }
            schema["then"] = { "required" => %w[template_version_id] }
          end
        end
      end

      # Every reason `config` is refused for a runner of `type`, as messages
      # that name the key.
      def errors(config, type)
        return [ "must be an object" ] unless config.is_a?(Hash)

        refusals = key_refusals(config.deep_stringify_keys, type.to_s)
        return refusals if refusals.any?

        value_errors(config.deep_stringify_keys, type.to_s)
      end

      # The value `config` holds for `path`, or the key's default.
      def value(config, path)
        key = KEYS.fetch(path)
        found = path.split(".").reduce(config.to_h.deep_stringify_keys) do |node, part|
          break nil unless node.is_a?(Hash) && node.key?(part)

          node[part]
        end
        found.nil? ? key.default : found
      end

      private

      def object(keys, prefix: "")
        schema = {
          "type" => "object",
          "additionalProperties" => false,
          "properties" => keys.to_h { |k| [ k.path.delete_prefix(prefix), k.property_schema ] }
        }
        required = keys.select(&:required).map { |k| k.path.delete_prefix(prefix) }
        schema["required"] = required if required.any?
        schema
      end

      def key_refusals(config, type)
        config.flat_map do |name, value|
          next [ EPHEMERAL ] if name == "ephemeral"
          next [ refusal(name, type) ].compact unless GROUPS.include?(name)
          next [] unless value.is_a?(Hash)

          value.keys.filter_map { |nested| refusal("#{name}.#{nested}", type) }
        end
      end

      def refusal(path, type)
        key = KEYS[path]
        return "#{path} is not a known setting" if key.nil?
        return "#{path} is not supported yet" if key.later
        return if key.applies_to?(type)

        "#{path} applies only to #{key.types.to_sentence} runners"
      end

      def value_errors(config, type)
        JSONSchemer.schema(for_type(type), format: true).validate(config).map { |error| message(error) }.uniq
      end

      def message(error)
        path = location(error["data_pointer"])
        schema = error["schema"].is_a?(Hash) ? error["schema"] : {}

        case error["type"]
        when "required"
          missing = error.dig("details", "missing_keys").to_a.map { |k| [ path, k ].compact_blank.join(".") }
          "#{missing.to_sentence} #{missing.one? ? 'is' : 'are'} required"
        when "minimum", "maximum"
          range = [ schema["minimum"], schema["maximum"] ].compact
          range.size == 2 ? "#{path} must be between #{range.join(' and ')}" : "#{path} is out of range"
        when "exclusiveMinimum" then "#{path} must be greater than #{schema['exclusiveMinimum']}"
        when "pattern"
          schema["pattern"] == ABSOLUTE_PATH["pattern"] ? "#{path} must be an absolute path" : "#{path} is not valid"
        when "enum" then "#{path} must be one of #{schema['enum'].join(', ')}"
        when "format" then "#{path} must be a #{schema['format'].upcase}"
        when "oneOf" then "#{path} must set exactly one of name or host_path"
        when "schema" then "#{path} is not a known setting"
        when "maxLength" then "#{path} is too long"
        when "minLength" then "#{path} can't be blank"
        when *TYPE_NAMES.keys then "#{path} must be #{Array(schema['type']).map { |t| TYPE_NAMES[t] }.join(' or ')}"
        else
          "#{path} #{error['error']}"
        end
      end

      # `/container/extra_mounts/0/source` as `container.extra_mounts[0].source`.
      def location(pointer)
        pointer.to_s.split("/").drop(1).reduce(+"") do |path, part|
          part.match?(/\A\d+\z/) ? path << "[#{part}]" : path << (path.empty? ? part : ".#{part}")
        end
      end
    end
  end
end
