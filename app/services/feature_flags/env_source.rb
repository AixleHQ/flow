# frozen_string_literal: true

module FeatureFlags
  # The ENV lock layer: FEATURE_<KEY> for each declared flag, read once at boot
  # from `Settings.feature_flags.env`. An unrecognised value raises InvalidEnv
  # naming the variable, because a typo in a kill switch is better caught at
  # deploy than silently ignored. A variable for an undeclared key is only
  # collected in #undeclared: removing a flag must not need an infra change first.
  #
  # A flag declared with `env_setting:` has a second lock: that legacy Settings
  # value (`coder.reap_enabled`, read by config/settings.yml from
  # `env_setting_variable`, e.g. CODER_REAP_ENABLED). The setting is true or
  # false only when its variable is set, and nil when it is not, so a settings
  # default never locks the flag. When FEATURE_<KEY> and the legacy variable are
  # both set, FEATURE_<KEY> wins: it is the flag's own lock, and a deployment
  # that sets it has moved to it. #variable_for names the variable that decides.
  #
  # `settings` is the settings tree (`Settings.to_h`); without it (the suite's
  # default) no legacy lock is read. With it, an env_setting path that names no
  # setting raises InvalidEnv, so a typo in the registry fails boot. Only the
  # values at the declared env_setting paths are kept: the full tree holds
  # secrets (secret_key_base, DB and OAuth credentials) that must not live on in
  # this process-wide object or show up in its #inspect. Copies (#merge,
  # #merge_settings, #with_registry) start from those kept values.
  class EnvSource
    PREFIX = "FEATURE_"
    RESERVED_PREFIX = "FEATURE_FLAGS_"
    ON = %w[on true 1].freeze
    OFF = %w[off false 0].freeze

    attr_reader :raw, :undeclared

    def initialize(env, registry:, settings: nil)
      @raw = env.to_h.transform_keys(&:to_s)
                .select { |name, _| name.start_with?(PREFIX) && !name.start_with?(RESERVED_PREFIX) }
                .freeze
      @registry = registry
      @settings = nil
      @values = {}
      @variables = {}
      undeclared = []
      errors = []

      @raw.each do |name, value|
        text = value.to_s.strip.downcase
        next if text.empty?

        definition = definition_for(name)
        if definition.nil?
          undeclared << name
        elsif ON.include?(text)
          lock(definition, true, name)
        elsif OFF.include?(text)
          lock(definition, false, name)
        else
          errors << "#{name} must be on/off/true/false/1/0, got #{value.to_s.strip.inspect}"
        end
      end

      @settings = read_settings(settings, errors) unless settings.nil?

      raise InvalidEnv, errors.join("; ") if errors.any?

      @settings&.freeze
      @values.freeze
      @variables.freeze
      @undeclared = undeclared.sort.freeze
      freeze
    end

    # true or false when an ENV variable locks the flag, nil when none is set.
    def value_for(key) = @values[key.to_s.to_sym]

    # The variable that locks the flag (FEATURE_<KEY> or its legacy
    # env_setting_variable), nil when none is set.
    def variable_for(key) = @variables[key.to_s.to_sym]

    # A copy with some variables replaced, validated against the same registry.
    def merge(overrides) = self.class.new(@raw.merge(overrides.to_h.transform_keys(&:to_s)), registry: @registry, settings: @settings)

    # A copy with some legacy settings replaced (`{ "coder.reap_enabled" => false }`).
    def merge_settings(overrides)
      settings = overrides.reduce(@settings || {}) { |tree, (path, value)| put(tree, path.to_s.split("."), value) }
      self.class.new(@raw, registry: @registry, settings: settings)
    end

    def with_registry(registry) = self.class.new(@raw, registry: registry, settings: @settings)

    private

    def lock(definition, value, variable)
      @values[definition.key] = value
      @variables[definition.key] = variable
    end

    # Locks the flags whose legacy setting is set, and returns the tree reduced
    # to the declared env_setting paths: the only part of `settings` kept.
    def read_settings(settings, errors)
      @registry.definitions.reduce({}) do |kept, definition|
        next kept if definition.env_setting.nil?

        found, value = dig(settings, definition.env_setting)
        if !found
          errors << "#{definition.key}: env_setting #{definition.env_setting} is not a setting"
        elsif ![ true, false, nil ].include?(value)
          errors << "#{definition.env_setting} (#{definition.env_setting_variable}) must be true, false or unset, got #{value.inspect}"
        else
          lock(definition, value, definition.env_setting_variable) if !value.nil? && !@values.key?(definition.key)
          kept = put(kept, definition.env_setting.split("."), value)
        end
        kept
      end
    end

    # [found, value]: a nil value is a setting whose variable is unset.
    def dig(tree, path)
      path.split(".").reduce([ true, tree ]) do |(_, node), segment|
        return [ false, nil ] unless node.respond_to?(:key?)

        name = [ segment.to_sym, segment ].find { |candidate| node.key?(candidate) }
        return [ false, nil ] if name.nil?

        [ true, node[name] ]
      end
    end

    def put(tree, segments, value)
      head, *rest = segments
      key = head.to_sym
      tree = tree.to_h.transform_keys(&:to_sym)
      tree.merge(key => rest.empty? ? value : put(tree[key] || {}, rest, value))
    end

    def definition_for(name)
      key = name.delete_prefix(PREFIX).downcase
      return unless @registry.declared?(key)

      definition = @registry.fetch(key)
      definition if definition.env_var == name
    end
  end
end
