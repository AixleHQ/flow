# frozen_string_literal: true

module FeatureFlags
  # The ENV lock layer, read once at boot from `Settings.feature_flags.env`:
  # FEATURE_<KEY> for each declared flag, and the flag's own `env:` variable
  # when it declares one (coder_reap: CODER_REAP_ENABLED). Both are parsed the
  # same way; when both are set, FEATURE_<KEY> wins. An unrecognised value
  # raises InvalidEnv naming the variable, because a typo in a kill switch is
  # better caught at deploy than silently ignored. A FEATURE_* variable for an
  # undeclared key is only collected in #undeclared: removing a flag must not
  # need an infra change first.
  class EnvSource
    PREFIX = "FEATURE_"
    ON = %w[on true 1].freeze
    OFF = %w[off false 0].freeze
    VALUES = ON.index_with(true).merge(OFF.index_with(false)).freeze

    attr_reader :raw, :undeclared

    def initialize(env, registry:)
      @raw = env.to_h.transform_keys(&:to_s).freeze
      @registry = registry
      @values = {}
      @variables = {}
      errors = []

      registry.definitions.each do |definition|
        definition.env_vars.each do |name| # FEATURE_<KEY> first: it wins
          text = @raw[name].to_s.strip.downcase
          next if text.empty?

          value = VALUES[text]
          if value.nil?
            errors << "#{name} must be on/off/true/false/1/0, got #{@raw[name].to_s.strip.inspect}"
          elsif !@values.key?(definition.key)
            @values[definition.key] = value
            @variables[definition.key] = name
          end
        end
      end
      raise InvalidEnv, errors.join("; ") if errors.any?

      declared = registry.definitions.flat_map(&:env_vars)
      @undeclared = @raw.select { |name, value| name.start_with?(PREFIX) && !declared.include?(name) && !value.to_s.strip.empty? }
                        .keys.sort.freeze
      @values.freeze
      @variables.freeze
      freeze
    end

    # true or false when an ENV variable locks the flag, nil when none is set.
    def value_for(key) = @values[key.to_s.to_sym]

    # The variable that locks the flag, nil when none is set.
    def variable_for(key) = @variables[key.to_s.to_sym]

    # A copy with some variables replaced, validated against the same registry.
    def merge(overrides) = self.class.new(@raw.merge(overrides.to_h.transform_keys(&:to_s)), registry: @registry)
  end
end
