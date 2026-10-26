# frozen_string_literal: true

module FeatureFlags
  # One resolved flag: the value, the layer that decided it (:env, :company,
  # :global, :default, or :unknown for an undeclared key in production), the
  # variable that locks it (FEATURE_<KEY> unless its legacy env_setting_variable
  # does) or would lock it, and the set layers it beat, highest
  # first, as `{ source:, value: }`. The declared default is never listed as shadowed.
  Resolution = Data.define(:key, :value, :source, :env_var, :shadowed) do
    def self.unknown(key)
      new(key: key.to_s.to_sym, value: false, source: :unknown,
          env_var: "#{EnvSource::PREFIX}#{key.to_s.upcase}", shadowed: [].freeze)
    end

    def enabled? = value
  end
end
