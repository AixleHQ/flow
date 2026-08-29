# frozen_string_literal: true

module UsageStatistics
  # Folds a batch of usage events into a session's UsageStatistic row without
  # ever loading the accumulated history into Ruby.
  #
  # The obvious implementation — read events_data, concatenate, re-aggregate the
  # whole array, write it back — is quadratic in the number of batches a session
  # produces, and the agent runtimes emit one roughly every two seconds. The read
  # side of that loop is what put both production web replicas over their memory
  # limit on 2026-08-28.
  #
  # Every quantity here is associative, so a batch can be folded in as a delta
  # instead: one statement that either inserts the row or increments what is
  # already there, reading nothing back. Concurrent batches for the same session
  # need no lock of their own — PostgreSQL serialises the conflicting upserts on
  # the unique index over terminal_session_id. The old path reached for a row
  # lock and did not get one either: `TerminalSession.lock.find_by` ran its
  # SELECT ... FOR UPDATE outside any transaction, so the lock was released as
  # the statement returned.
  #
  # Writing the increment in SQL means Active Record's validations do not run.
  # That is safe for exactly the reason the increment is possible at all: the
  # numericality rules on UsageStatistic hold by construction here, since every
  # delta is non-negative and adding a non-negative delta to a non-negative
  # column cannot produce a negative one. Anything that needs to reject a value
  # rather than accumulate it does not belong on this path.
  class Accumulator
    Delta = Struct.new(
      :input_tokens, :output_tokens, :cache_write_tokens, :cache_read_tokens,
      :total_cents, :models, :count,
      keyword_init: true
    )

    # events: the batch just parsed out of a runtime's telemetry, in the shape
    # the adapters already build — {"model" =>, "timestamp" =>, "tokenUsage" => {...}}.
    def self.record(terminal_session:, events:, source: "otlp")
      new(terminal_session: terminal_session, events: events, source: source).record
    end

    def initialize(terminal_session:, events:, source: "otlp")
      @terminal_session = terminal_session
      @events = Array(events)
      @source = source
    end

    def record
      return :accepted if @events.empty?

      connection = UsageStatistic.connection
      connection.exec_update(upsert_sql, "UsageStatistics::Accumulator Upsert")
      # Raw DML does not invalidate Active Record's query cache the way a model
      # write does, and the cache is live for the whole request. Without this, a
      # read of UsageStatistic later in the same request still answers from before
      # the upsert.
      connection.clear_query_cache

      :ok
    end

    private

    def delta
      @delta ||= @events.each_with_object(
        Delta.new(
          input_tokens: 0, output_tokens: 0, cache_write_tokens: 0,
          cache_read_tokens: 0, total_cents: 0.0, models: [], count: @events.size
        )
      ) do |event, acc|
        usage = event["tokenUsage"] || {}
        acc.input_tokens       += usage["inputTokens"].to_i
        acc.output_tokens      += usage["outputTokens"].to_i
        acc.cache_write_tokens += usage["cacheWriteTokens"].to_i
        acc.cache_read_tokens  += usage["cacheReadTokens"].to_i
        acc.total_cents        += usage["totalCents"].to_f

        model = event["model"]
        acc.models << model if model.present? && !acc.models.include?(model)
      end
    end

    def total_tokens
      delta.input_tokens + delta.output_tokens + delta.cache_write_tokens + delta.cache_read_tokens
    end

    # Both halves of the upsert build `models` the same way — out of a JSON array
    # bind rather than a text[] literal, so nothing has to hand-escape a Postgres
    # array. The ON CONFLICT branch unions it with what is already stored and
    # sorts, so the column stays a deterministic set rather than depending on the
    # order batches happened to arrive in.
    def upsert_sql
      ActiveRecord::Base.sanitize_sql_array([ <<~SQL, binds ])
        INSERT INTO usage_statistics (
          terminal_session_id, source,
          events_data, events_count,
          input_tokens, output_tokens, cache_write_tokens, cache_read_tokens,
          tokens, total_cents_precise, cost_cents, models,
          created_at, updated_at
        ) VALUES (
          :terminal_session_id, :source,
          CAST(:events AS jsonb), :count,
          :input_tokens, :output_tokens, :cache_write_tokens, :cache_read_tokens,
          :tokens, :total_cents, CAST(CEIL(:total_cents) AS bigint),
          ARRAY(SELECT jsonb_array_elements_text(CAST(:models AS jsonb))),
          NOW(), NOW()
        )
        ON CONFLICT (terminal_session_id) DO UPDATE SET
          source             = EXCLUDED.source,
          events_data        = COALESCE(usage_statistics.events_data, '[]'::jsonb) || EXCLUDED.events_data,
          events_count       = usage_statistics.events_count       + EXCLUDED.events_count,
          input_tokens       = usage_statistics.input_tokens       + EXCLUDED.input_tokens,
          output_tokens      = usage_statistics.output_tokens      + EXCLUDED.output_tokens,
          cache_write_tokens = usage_statistics.cache_write_tokens + EXCLUDED.cache_write_tokens,
          cache_read_tokens  = usage_statistics.cache_read_tokens  + EXCLUDED.cache_read_tokens,
          tokens             = usage_statistics.tokens             + EXCLUDED.tokens,
          total_cents_precise = usage_statistics.total_cents_precise + EXCLUDED.total_cents_precise,
          cost_cents         = CAST(
            CEIL(usage_statistics.total_cents_precise + EXCLUDED.total_cents_precise) AS bigint
          ),
          models = ARRAY(
            SELECT DISTINCT m
            FROM unnest(usage_statistics.models || EXCLUDED.models) AS m
            ORDER BY m
          ),
          updated_at = NOW()
      SQL
    end

    def binds
      {
        terminal_session_id: @terminal_session.id,
        source: @source,
        events: @events.to_json,
        count: delta.count,
        input_tokens: delta.input_tokens,
        output_tokens: delta.output_tokens,
        cache_write_tokens: delta.cache_write_tokens,
        cache_read_tokens: delta.cache_read_tokens,
        tokens: total_tokens,
        total_cents: delta.total_cents,
        models: delta.models.to_json
      }
    end
  end
end
