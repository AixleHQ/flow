# frozen_string_literal: true

module LlmCalls
  # Estimates the cost of a call whose runtime reported tokens but no cost, from the list
  # prices in config/llm_prices.yml or a price list the caller fetched itself (Grok reads
  # the xAI catalogue). An estimate, never a bill. Returns cents, or nil when the model
  # has no price — an unpriced call is unknown, not free.
  #
  # `input` is uncached input; cache reads and writes are counted apart, as on llm_calls.
  class Pricing
    TABLE_PATH = Rails.root.join("config/llm_prices.yml")
    RATE_KEYS = %w[input cache_read cache_write output].freeze

    class << self
      # sheet: { model id => { "input" =>, "cache_read" =>, "output" => } } in USD per
      # million tokens, consulted before the table.
      # single_request: false for a turn or a whole session, whose prompt size says
      # nothing about any one request, so long-context rates never apply.
      def cents(model:, input: 0, output: 0, cache_read: 0, cache_write: 0, at: Time.current,
                single_request: true, sheet: nil)
        entry = lookup(sheet, model) || lookup(table, model)
        return nil if entry.nil?

        rates = rates_for(entry, at.to_date)
        prompt = input.to_i + cache_read.to_i + cache_write.to_i
        long = entry["long_context"]
        rates = rates.merge(long.slice(*RATE_KEYS)) if single_request && long && prompt > long["above"].to_i

        usd = (input.to_i * rates["input"].to_f) +
              (cache_read.to_i * (rates["cache_read"] || rates["input"]).to_f) +
              (cache_write.to_i * (rates["cache_write"] || rates["input"]).to_f) +
              (output.to_i * rates["output"].to_f)
        (usd / 10_000.0).round(6)
      end

      # An adapter's usage event, priced in place: tokenUsage.totalCents and costBasis
      # ("priced", or "unknown" with no cents when the model has no price).
      def price_event!(event, single_request: true, sheet: nil)
        usage = event["tokenUsage"]
        cents = cents(
          model: event["model"], input: usage["inputTokens"], output: usage["outputTokens"],
          cache_read: usage["cacheReadTokens"], cache_write: usage["cacheWriteTokens"],
          at: EventTime.parse(event["timestamp"]) || Time.current, single_request: single_request, sheet: sheet
        )
        usage["totalCents"] = cents
        event["costBasis"] = cents ? "priced" : "unknown"
        warn_unpriced(event["model"]) if cents.nil?
        event
      end

      def priced?(model)
        lookup(table, model).present?
      end

      def table
        @table ||= YAML.safe_load_file(TABLE_PATH, permitted_classes: [ Date ]).fetch("models").freeze
      end

      private

      # Once per model and process: usage arrives every few seconds, and the point is to
      # learn that the table is missing a model, not to count its calls.
      def warn_unpriced(model)
        @warned ||= Concurrent::Set.new
        return unless @warned.add?(model.to_s)

        Rails.logger.warn("[LlmCalls::Pricing] no price for model #{model.inspect}; add it to config/llm_prices.yml")
      end

      def lookup(prices, model)
        name = ModelName.canonical(model)
        return nil if prices.blank? || name.nil?

        key = prices.keys.select { |k| name == k || name.start_with?("#{k}-") }.max_by(&:length)
        key && prices[key].stringify_keys
      end

      def rates_for(entry, date)
        Array(entry["changes"]).sort_by { |change| change["from"] }.reduce(entry.slice(*RATE_KEYS)) do |rates, change|
          change["from"] <= date ? rates.merge(change.slice(*RATE_KEYS)) : rates
        end
      end
    end
  end
end
