# frozen_string_literal: true

module FeatureFlags
  # The declared flags, validated and frozen. Anything invalid raises
  # InvalidRegistry listing every problem, so a bad entry fails boot rather than
  # the first request that checks it.
  class Registry
    KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/
    # FEATURE_FLAGS_* is the system's own settings, so no key may map into it.
    RESERVED_KEY = /\Aflags(_|\z)/
    KINDS = %w[release ops].freeze
    SCOPES = %w[company global].freeze
    REQUIRED = %w[description owner kind scope default].freeze
    OPTIONAL = %w[client introduced remove_by env_setting env_setting_variable].freeze
    # A legacy Settings path (`coder.reap_enabled`) and the variable config/settings.yml
    # reads it from (`CODER_REAP_ENABLED`): together, a second ENV lock (EnvSource).
    SETTING_PATH = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
    SETTING_VARIABLE = /\A[A-Z][A-Z0-9_]*\z/

    class Definition < Data.define(:key, :description, :owner, :kind, :scope, :default, :client,
                                   :introduced, :remove_by, :env_setting, :env_setting_variable)
      def env_var = "#{EnvSource::PREFIX}#{key.to_s.upcase}"
      # Every variable that can lock the flag, FEATURE_<KEY> first.
      def env_vars = [ env_var, env_setting_variable ].compact
      def company_scoped? = scope == :company
      def global? = scope == :global
      def release? = kind == :release
      def client? = client
    end

    def self.load(path)
      source = Pathname(path)
      parsed = YAML.safe_load(source.read, permitted_classes: [ Date ], aliases: false)
      new(parsed || {}, source: source.to_s.delete_prefix("#{Rails.root}/"))
    rescue Psych::Exception => e
      raise InvalidRegistry, "#{path}: #{e.message}"
    end

    def initialize(entries, source: "feature flag registry")
      raise InvalidRegistry, "#{source}: must be a mapping of flag keys" unless entries.is_a?(Hash)

      errors = []
      @definitions = entries.each_with_object({}) do |(key, attributes), definitions|
        problems = problems_with(key.to_s, attributes)
        if problems.empty?
          definitions[key.to_sym] = build(key.to_sym, attributes)
        else
          errors.concat(problems.map { |problem| "#{key}: #{problem}" })
        end
      end.freeze

      raise InvalidRegistry, "#{source} is invalid:\n  #{errors.join("\n  ")}" if errors.any?

      freeze
    end

    def fetch(key)
      @definitions.fetch(key.to_s.to_sym) { raise UnknownFlag, key }
    end

    def declared?(key) = @definitions.key?(key.to_s.to_sym)
    def keys = @definitions.keys
    def definitions = @definitions.values
    def empty? = @definitions.empty?

    private

    def problems_with(key, attributes)
      return [ "key must match #{KEY_FORMAT.inspect}" ] unless key.match?(KEY_FORMAT)
      return [ "key maps to the reserved FEATURE_FLAGS_* prefix" ] if key.match?(RESERVED_KEY)
      return [ "must be a mapping of attributes" ] unless attributes.is_a?(Hash)

      problems = []
      missing = REQUIRED.reject { |name| attributes.key?(name) && !attributes[name].nil? }
      problems << "missing #{missing.join(', ')}" if missing.any?
      unknown = attributes.keys - REQUIRED - OPTIONAL
      problems << "unknown attribute #{unknown.join(', ')}" if unknown.any?

      problems << "description must be text" if attributes.key?("description") && blank_text?(attributes["description"])
      problems << "owner must be text" if attributes.key?("owner") && blank_text?(attributes["owner"])
      problems << "kind must be one of #{KINDS.join(', ')}" if attributes.key?("kind") && !KINDS.include?(attributes["kind"])
      problems << "scope must be one of #{SCOPES.join(', ')}" if attributes.key?("scope") && !SCOPES.include?(attributes["scope"])
      problems << "default must be true or false" if attributes.key?("default") && !boolean?(attributes["default"])
      problems << "client must be true or false" if attributes.key?("client") && !boolean?(attributes["client"])
      problems << "introduced must be a date (YYYY-MM-DD)" if attributes.key?("introduced") && !attributes["introduced"].is_a?(Date)
      if attributes["kind"] == "release" && !attributes["remove_by"].is_a?(Date)
        problems << "remove_by (YYYY-MM-DD) is required for kind: release"
      elsif attributes.key?("remove_by") && !attributes["remove_by"].is_a?(Date)
        problems << "remove_by must be a date (YYYY-MM-DD)"
      end
      problems.concat(env_setting_problems(attributes))
    end

    def env_setting_problems(attributes)
      path = attributes["env_setting"]
      variable = attributes["env_setting_variable"]
      return [] if path.nil? && variable.nil?
      return [ "env_setting_variable is required with env_setting" ] if variable.nil?
      return [ "env_setting is required with env_setting_variable" ] if path.nil?

      problems = []
      if !path.is_a?(String) || !path.match?(SETTING_PATH)
        problems << "env_setting must be a dotted Settings path (e.g. coder.reap_enabled)"
      elsif path.start_with?("feature_flags.")
        problems << "env_setting must not point into the feature_flags settings"
      end
      if !variable.is_a?(String) || !variable.match?(SETTING_VARIABLE)
        problems << "env_setting_variable must be an upper-case variable name"
      elsif variable.start_with?(EnvSource::PREFIX)
        problems << "env_setting_variable must not be a FEATURE_* variable"
      end
      problems
    end

    def build(key, attributes)
      Definition.new(
        key: key,
        description: attributes["description"].strip.freeze,
        owner: attributes["owner"].strip.freeze,
        kind: attributes["kind"].to_sym,
        scope: attributes["scope"].to_sym,
        default: attributes["default"],
        client: attributes.fetch("client", false),
        introduced: attributes["introduced"]&.freeze,
        remove_by: attributes["remove_by"]&.freeze,
        env_setting: attributes["env_setting"]&.dup&.freeze,
        env_setting_variable: attributes["env_setting_variable"]&.dup&.freeze
      )
    end

    def blank_text?(value) = !value.is_a?(String) || value.strip.empty?
    def boolean?(value) = [ true, false ].include?(value)
  end
end
