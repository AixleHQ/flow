# frozen_string_literal: true

module FeatureFlags
  # The ENV lock layer: FEATURE_<KEY> for each declared flag, read once at boot
  # from `Settings.feature_flags.env`. An unrecognised value raises InvalidEnv
  # naming the variable, because a typo in a kill switch is better caught at
  # deploy than silently ignored. A variable for an undeclared key is only
  # collected in #undeclared: removing a flag must not need an infra change first.
  class EnvSource
    PREFIX = "FEATURE_"
    RESERVED_PREFIX = "FEATURE_FLAGS_"
    ON = %w[on true 1].freeze
    OFF = %w[off false 0].freeze

    attr_reader :raw, :undeclared

    def initialize(env, registry:)
      @raw = env.to_h.transform_keys(&:to_s)
                .select { |name, _| name.start_with?(PREFIX) && !name.start_with?(RESERVED_PREFIX) }
                .freeze
      @registry = registry
      @values = {}
      undeclared = []
      errors = []

      @raw.each do |name, value|
        text = value.to_s.strip.downcase
        next if text.empty?

        definition = definition_for(name)
        if definition.nil?
          undeclared << name
        elsif ON.include?(text)
          @values[definition.key] = true
        elsif OFF.include?(text)
          @values[definition.key] = false
        else
          errors << "#{name} must be on/off/true/false/1/0, got #{value.to_s.strip.inspect}"
        end
      end

      raise InvalidEnv, errors.join("; ") if errors.any?

      @values.freeze
      @undeclared = undeclared.sort.freeze
      freeze
    end

    # true or false when FEATURE_<KEY> locks the flag, nil when it is not set.
    def value_for(key) = @values[key.to_s.to_sym]

    # A copy with some variables replaced, validated against the same registry.
    def merge(overrides) = self.class.new(@raw.merge(overrides.to_h.transform_keys(&:to_s)), registry: @registry)

    def with_registry(registry) = self.class.new(@raw, registry: registry)

    private

    def definition_for(name)
      key = name.delete_prefix(PREFIX).downcase
      return unless @registry.declared?(key)

      definition = @registry.fetch(key)
      definition if definition.env_var == name
    end
  end
end
