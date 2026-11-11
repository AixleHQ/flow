# frozen_string_literal: true

module LlmCalls
  # Turns a session's usage events (usage_statistics.events_data) into llm_calls rows.
  #
  # Each row is keyed by the event's position in that log, so running it again — a
  # late telemetry batch, the backfill task — only adds the rows that are missing and
  # never rewrites one that may already have been exported.
  #
  # What an event means comes from the adapter that wrote it (BaseAdapter#llm_call_traits):
  # the canonical source, granularity and provider. Events written before adapters
  # stamped `costBasis` carry the old conventions — input counted with the cache for
  # some runtimes, 0 for an unknown cost — and are read accordingly.
  class Materializer
    def self.call(terminal_session)
      new(terminal_session).call
    end

    def initialize(terminal_session)
      @session = terminal_session
    end

    def call
      return 0 unless AgentCredentialsService::ADAPTERS.key?(@session.agent_type)

      events = Array(UsageStatistic.where(terminal_session_id: @session.id).pick(:events_data))
      return 0 if events.empty?

      existing = LlmCall.where(terminal_session_id: @session.id).pluck(:event_index).to_set
      rows = events.each_with_index.filter_map do |event, index|
        next if existing.include?(index) || !event.is_a?(Hash)

        row(event, index)
      end
      return 0 if rows.empty?

      LlmCall.insert_all(rows, unique_by: %i[terminal_session_id event_index], returning: false)
      rows.size
    end

    private

    def adapter
      @adapter ||= AgentCredentialsService::ADAPTERS.fetch(@session.agent_type).new
    end

    def step_run
      return @step_run if defined?(@step_run)

      @step_run = @session.step_run
    end

    def row(event, index)
      traits = adapter.llm_call_traits(event)
      if traits.nil?
        Rails.logger.warn("[LlmCalls::Materializer] session #{@session.id}: no traits for source #{event['source'].inspect}")
        return nil
      end

      tokens = tokens(event, traits)
      cents, basis = cost(event, traits)
      now = Time.current

      {
        terminal_session_id: @session.id,
        workflow_run_id: step_run&.workflow_run_id,
        step_run_id: step_run&.id,
        event_index: index,
        occurred_at: occurred_at(event["timestamp"]),
        model: ModelName.canonical(event["model"]) || "unknown",
        provider: adapter.llm_provider(event["model"]),
        **tokens,
        total_cents_precise: cents,
        cost_basis: basis,
        granularity: traits.fetch(:granularity),
        source: traits.fetch(:source),
        duration_ms: event["durationMs"]&.to_i,
        created_at: now,
        updated_at: now
      }
    end

    def tokens(event, traits)
      usage = event["tokenUsage"].is_a?(Hash) ? event["tokenUsage"] : {}
      counts = {
        input_tokens: usage["inputTokens"],
        output_tokens: usage["outputTokens"],
        cache_read_tokens: usage["cacheReadTokens"],
        cache_write_tokens: usage["cacheWriteTokens"]
      }.transform_values { |value| value&.to_i }

      if legacy?(event) && traits[:legacy_input_includes_cache] && counts[:input_tokens]
        counts[:input_tokens] = [ counts[:input_tokens] - counts[:cache_read_tokens].to_i, 0 ].max
      end
      counts
    end

    def cost(event, traits)
      usage = event["tokenUsage"].is_a?(Hash) ? event["tokenUsage"] : {}
      cents = usage["totalCents"]
      cents = event["creditsUsed"].to_f * event["creditRateUsd"].to_f * 100 if cents.nil? && event["creditsUsed"]

      unless legacy?(event)
        basis = event["costBasis"]
        return basis == "unknown" || cents.nil? ? [ nil, "unknown" ] : [ cents.to_f, basis ]
      end

      cents.to_f.positive? ? [ cents.to_f.round(6), traits.fetch(:cost_basis) ] : [ nil, "unknown" ]
    end

    def legacy?(event)
      !event.key?("costBasis")
    end

    # An event with no time of its own is a total for the session, which ended then.
    def occurred_at(raw)
      EventTime.parse(raw) || @session.finished_at || Time.current
    end
  end
end
