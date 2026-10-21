# frozen_string_literal: true

module FeatureFlags
  # Runtime values held in process memory. It is the store in every environment
  # until the database-backed one exists, and stays the store in tests, where
  # test/support/feature_flags_helper.rb writes to it and resets it per test.
  # Each write swaps in a new frozen Snapshot, so a reader never sees half a change.
  class MemoryStore
    def initialize
      @lock = Mutex.new
      @snapshot = Snapshot::EMPTY
    end

    attr_reader :snapshot

    def replace(snapshot)
      @lock.synchronize { @snapshot = snapshot }
    end

    def reset! = replace(Snapshot::EMPTY)

    def set_global(key, enabled) = update(key) { |flag| flag.merge(global: enabled) }
    def clear_global(key) = set_global(key, nil)

    def set_override(key, company_id, enabled)
      update(key) { |flag| flag.merge(overrides: flag[:overrides].merge(company_id => enabled)) }
    end

    def remove_override(key, company_id)
      update(key) { |flag| flag.merge(overrides: flag[:overrides].except(company_id)) }
    end

    private

    def update(key)
      @lock.synchronize do
        flags = @snapshot.to_h
        current = flags.fetch(key.to_s.to_sym, { global: nil, overrides: {} })
        @snapshot = Snapshot.new(flags.merge(key.to_s.to_sym => yield(current)))
      end
    end
  end
end
