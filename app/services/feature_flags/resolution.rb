# frozen_string_literal: true

module FeatureFlags
  # One resolved flag: the value, the layer that decided it (:env, :company,
  # :global, :default, or :unknown for an undeclared key in production), and
  # the variable that locks it, or FEATURE_<KEY> when none does.
  Resolution = Data.define(:key, :value, :source, :env_var) do
    def self.unknown(key)
      new(key: key.to_s.to_sym, value: false, source: :unknown, env_var: "#{EnvSource::PREFIX}#{key.to_s.upcase}")
    end
  end
end
