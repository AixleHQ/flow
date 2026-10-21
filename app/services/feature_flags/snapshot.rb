# frozen_string_literal: true

module FeatureFlags
  # The runtime values at one moment, frozen:
  # `{ key => { global: true | false | nil, overrides: { company_id => true | false } } }`.
  # A nil global means "use the declared default". Keys no flag declares are
  # carried but never consulted by the resolver.
  class Snapshot
    def initialize(flags = {})
      @flags = flags.to_h do |key, value|
        [ key.to_s.to_sym, { global: value[:global], overrides: value.fetch(:overrides, {}).dup.freeze }.freeze ]
      end.freeze
      freeze
    end

    EMPTY = new

    def global(key) = @flags.dig(key.to_s.to_sym, :global)
    def override(key, company_id) = @flags.dig(key.to_s.to_sym, :overrides, company_id)
    def to_h = @flags
  end
end
