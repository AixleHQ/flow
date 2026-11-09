# frozen_string_literal: true

module Sessions
  module Checks
    # What the checks keep between passes, in terminal_sessions.metadata, written once per
    # session per pass.
    #
    # Each check owns its keys (Base.kept_keys) and reads and writes them through its own
    # View, which refuses any other key. The changes are collected over the pass and
    # written by Sessions::Monitor in one UPDATE (#write!), which touches only those keys,
    # so a key another writer set in the meantime stays as it is.
    #
    # Only observations are kept this way. A check's action writes what it must write
    # before it acts, under the session's row lock, at once: a reminder is counted before
    # it is typed, a pause is recorded before the run is paused.
    class KeptState
      def initialize(session)
        @session = session
        @set = {}
        @removed = []
      end

      def for(check_class)
        View.new(self, check_class.kept_keys, check_class.name)
      end

      def [](key)
        return @set[key] if @set.key?(key)
        return nil if @removed.include?(key)

        (@session.metadata || {})[key]
      end

      def store(key, value)
        @removed.delete(key)
        @set[key] = value
      end

      def delete(key)
        @set.delete(key)
        @removed << key if (@session.metadata || {}).key?(key) && @removed.exclude?(key)
      end

      def changed? = @set.any? || @removed.any?

      def write!
        return false unless changed?

        @session.update_jsonb_keys!(:metadata, set: @set, remove: @removed)
        @set = {}
        @removed = []
        true
      end

      # One check's keys.
      class View
        def initialize(state, keys, owner)
          @state = state
          @keys = keys
          @owner = owner
        end

        def [](key) = @state[own!(key)]

        def store(pairs)
          pairs.each { |key, value| @state.store(own!(key), value) }
        end

        def delete(*keys)
          keys.each { |key| @state.delete(own!(key)) }
        end

        private

        def own!(key)
          return key if @keys.include?(key)

          raise ArgumentError, "#{@owner} does not own the kept key #{key.inspect}"
        end
      end
    end
  end
end
