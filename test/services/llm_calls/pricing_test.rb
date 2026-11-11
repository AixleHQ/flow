# frozen_string_literal: true

require "test_helper"

module LlmCalls
  class PricingTest < ActiveSupport::TestCase
    test "uncached input, cache reads and output are each priced at their own rate" do
      # gpt-5: $1.25 input, $0.125 cached, $10 output per million.
      cents = Pricing.cents(model: "gpt-5", input: 1_000_000, cache_read: 1_000_000, output: 100_000)

      assert_in_delta 125.0 + 12.5 + 100.0, cents
    end

    test "a snapshot or variant of a model takes its price, a different version does not" do
      assert_equal Pricing.cents(model: "gpt-5.1", input: 1_000), Pricing.cents(model: "gpt-5.1-codex-max", input: 1_000)
      assert_equal Pricing.cents(model: "gpt-5", input: 1_000), Pricing.cents(model: "gpt-5-2025-08-07", input: 1_000)
      assert_nil Pricing.cents(model: "gpt-5.7", input: 1_000)
    end

    test "the longest matching key wins" do
      # gpt-5-mini is $0.25 per million input, gpt-5 is $1.25.
      assert_in_delta 25.0, Pricing.cents(model: "gpt-5-mini-2025-08-07", input: 1_000_000)
      assert_in_delta 25.0, Pricing.cents(model: "gpt-5.1-codex-mini", input: 1_000_000)
    end

    test "a model with no price is unknown, never free" do
      assert_nil Pricing.cents(model: "some-new-model", input: 10, output: 10)
      assert_nil Pricing.cents(model: nil, input: 10)
    end

    test "cache reads and writes fall back to the input rate where the table has none" do
      # gpt-5-pro has no cached rate: $15 per million for every input token.
      assert_in_delta 1500.0 * 3, Pricing.cents(model: "gpt-5-pro", input: 1_000_000, cache_read: 1_000_000,
                                                cache_write: 1_000_000)
    end

    test "a single request over the long-context threshold is priced at the long-context rate" do
      # gemini-2.5-pro: $1.25 / $10 up to 200k prompt tokens, $2.50 / $15 above.
      short = Pricing.cents(model: "gemini-2.5-pro", input: 150_000, cache_read: 50_000, output: 1_000)
      long = Pricing.cents(model: "gemini-2.5-pro", input: 150_000, cache_read: 50_001, output: 1_000)

      assert_in_delta (150_000 * 1.25) + (50_000 * 0.125) + (1_000 * 10.0), short * 10_000
      assert_in_delta (150_000 * 2.50) + (50_001 * 0.25) + (1_000 * 15.0), long * 10_000
    end

    test "a turn or a session total never takes the long-context rate" do
      base = Pricing.cents(model: "gemini-2.5-pro", input: 300_000, single_request: false)

      assert_in_delta 300_000 * 1.25 / 10_000, base
    end

    test "a rate change applies from its date" do
      # gemini-4-argon: $2 input until 2026-11-30, $4 from 2026-12-01.
      before = Pricing.cents(model: "gemini-4-argon-high", input: 1_000_000, at: Time.utc(2026, 11, 30, 23))
      after = Pricing.cents(model: "gemini-4-argon-high", input: 1_000_000, at: Time.utc(2026, 12, 1))

      assert_in_delta 200.0, before
      assert_in_delta 400.0, after
    end

    test "a caller's price list comes before the table" do
      sheet = { "grok-4" => { "input" => 3.0, "cache_read" => 0.75, "output" => 15.0 } }

      assert_in_delta 300.0, Pricing.cents(model: "grok-4", input: 1_000_000, sheet: sheet)
      assert_in_delta 125.0, Pricing.cents(model: "gpt-5", input: 1_000_000, sheet: sheet)
    end

    test "an event is priced in place, and stamped unknown when it cannot be" do
      priced = Pricing.price_event!({ "model" => "gpt-5", "timestamp" => "1768478400000",
                                      "tokenUsage" => { "inputTokens" => 1_000_000, "outputTokens" => 0 } })
      unpriced = Pricing.price_event!({ "model" => "mystery", "tokenUsage" => { "inputTokens" => 5 } })

      assert_in_delta 125.0, priced.dig("tokenUsage", "totalCents")
      assert_equal "priced", priced["costBasis"]
      assert_nil unpriced.dig("tokenUsage", "totalCents")
      assert_equal "unknown", unpriced["costBasis"]
    end

    # Adding a model to a runtime Flow prices without adding its price would quietly turn
    # its cost unknown; the fallback catalogues are the models those runtimes ship with.
    test "every model a priced runtime offers by default has a price" do
      offered = Agents::GeminiCliAdapter::FALLBACK_GEMINI_MODELS.pluck(:model_id) +
                Agents::CodexAdapter::FALLBACK_MODEL_MIGRATIONS.to_a.flatten +
                Agents::AntigravityCliAdapter::FALLBACK_MODELS.pluck(:model_id)

      assert_empty offered.uniq.reject { |model| Pricing.priced?(model) }
    end

    test "every table entry has the rates a price needs" do
      Pricing.table.each do |model, entry|
        assert entry["input"].is_a?(Numeric) && entry["output"].is_a?(Numeric), "#{model} needs input and output rates"
        Array(entry["changes"]).each { |change| assert_kind_of Date, change["from"], "#{model} change needs a date" }
        assert_operator entry.dig("long_context", "above").to_i, :>, 0, model if entry["long_context"]
      end
    end
  end
end
