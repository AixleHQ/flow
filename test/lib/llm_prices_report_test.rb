# frozen_string_literal: true

require "test_helper"
require "open3"

# bin/llm-prices-report keeps config/llm_prices.yml honest against LiteLLM's public list.
class LlmPricesReportTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("bin/llm-prices-report").to_s

  test "reads the shipped table" do
    output = report(table: File.read(Rails.root.join("config/llm_prices.yml")), source: {})

    assert_match(/^<!-- differences: 0 -->$/, output)
    assert_includes output, "- `gpt-6-sol`"
  end

  test "reports a rate that differs, finds a model under a provider namespace or its source key, and skips none" do
    table = <<~YAML
      reviewed_on: #{Date.today - 10}
      models:
        gpt-x: { input: 2.00, cache_read: 0.20, output: 10.00, long_context: { above: 272000, input: 4.00, output: 15.00 } }
        gemini-y: { input: 0.30, output: 2.50 }
        gemini-z: { source: gemini-z-preview, input: 1.00, output: 5.00 }
        house-model: { input: 1.00, output: 1.00 }
    YAML
    source = {
      "gpt-x" => { "input_cost_per_token" => 2e-06, "cache_read_input_token_cost" => 1e-07, "output_cost_per_token" => 1e-05,
                   "input_cost_per_token_above_272k_tokens" => 4e-06, "output_cost_per_token_above_272k_tokens" => 1.5e-05 },
      "gemini/gemini-y" => { "input_cost_per_token" => 3e-07, "output_cost_per_token" => 2.5e-06 },
      "gemini-z-preview" => { "input_cost_per_token" => 1e-06, "output_cost_per_token" => 5e-06 }
    }

    output = report(table: table, source: source)

    assert_match(/^<!-- differences: 1 -->$/, output)
    assert_match(/^<!-- review-overdue: 0 -->$/, output)
    assert_includes output, "| `gpt-x` | `gpt-x` | cache_read | $0.2 | $0.1 |"
    assert_includes output, "- `house-model`"
    assert_not_includes output, "- `gemini-y`"
    assert_not_includes output, "- `gemini-z`"
  end

  test "compares the rate in effect today, not one scheduled for later" do
    table = <<~YAML
      reviewed_on: #{Date.today}
      models:
        m: { input: 1.00, output: 2.00, changes: [ { from: #{Date.today + 30}, input: 9.00, output: 9.00 } ] }
        n: { input: 1.00, output: 2.00, changes: [ { from: #{Date.today - 30}, input: 3.00, output: 4.00 } ] }
    YAML
    source = {
      "m" => { "input_cost_per_token" => 1e-06, "output_cost_per_token" => 2e-06 },
      "n" => { "input_cost_per_token" => 3e-06, "output_cost_per_token" => 4e-06 }
    }

    assert_match(/^<!-- differences: 0 -->$/, report(table: table, source: source))
  end

  test "a table not reviewed for ninety days is overdue even when every rate matches" do
    table = "reviewed_on: #{Date.today - 91}\nmodels:\n  m: { input: 1.00, output: 2.00 }\n"
    source = { "m" => { "input_cost_per_token" => 1e-06, "output_cost_per_token" => 2e-06 } }

    output = report(table: table, source: source)

    assert_match(/^<!-- differences: 0 -->$/, output)
    assert_match(/^<!-- review-overdue: 1 -->$/, output)
  end

  private

  def report(table:, source:)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "table.yml"), table)
      File.write(File.join(dir, "source.json"), source.to_json)
      env = { "LLM_PRICES_TABLE" => File.join(dir, "table.yml"), "LLM_PRICES_SOURCE" => File.join(dir, "source.json") }
      output, status = Open3.capture2e(env, SCRIPT)
      assert status.success?, output
      output
    end
  end
end
