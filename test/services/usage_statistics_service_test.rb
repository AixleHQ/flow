# frozen_string_literal: true

require "test_helper"

class UsageStatisticsServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :running, user: @user, project: @project)
  end

  test "process persists usage and returns ok for a valid OTLP payload" do
    payload = otlp_payload(
      otlp_resource_metric(
        token: @session.route_token,
        tokens: { input: 120, output: 30, cacheRead: 10, cacheCreation: 5 },
        cost_usd: 0.5,
        model: "claude-sonnet-4-6"
      )
    )

    result = nil
    assert_difference("UsageStatistic.count", 1) do
      result = UsageStatisticsService.process(payload.to_json)
    end

    assert_equal :ok, result.status
    assert_nil result.error

    stat = @session.reload.usage_statistic
    assert stat.present?, "expected a usage_statistic to be persisted for the session"
    assert_equal 120, stat.input_tokens
    assert_equal 30, stat.output_tokens
    assert_equal 10, stat.cache_read_tokens
    assert_equal 5, stat.cache_write_tokens
    assert_equal 50, stat.cost_cents
    assert_equal "otlp", stat.source
    assert_equal 1, stat.events_count
    assert_equal [ "claude-sonnet-4-6" ], stat.models
    assert_equal 165, stat.total_tokens
  end

  test "process persists a usage_statistic for every referenced session" do
    other_session = create(:terminal_session, :running, user: @user, project: @project)

    payload = otlp_payload(
      otlp_resource_metric(token: @session.route_token, tokens: { input: 100 }, cost_usd: 0.1),
      otlp_resource_metric(token: other_session.route_token, tokens: { output: 200 }, cost_usd: 0.2)
    )

    result = nil
    assert_difference("UsageStatistic.count", 2) do
      result = UsageStatisticsService.process(payload.to_json)
    end

    assert_equal :ok, result.status
    assert_equal 100, @session.reload.usage_statistic.input_tokens
    assert_equal 200, other_session.reload.usage_statistic.output_tokens
  end

  test "process returns accepted without persisting when payload carries no session token" do
    result = nil
    assert_no_difference("UsageStatistic.count") do
      result = UsageStatisticsService.process('{"resourceMetrics":[]}')
    end

    assert_equal :accepted, result.status
    assert_nil result.error
  end

  test "process returns accepted without persisting when the session has no usage to record" do
    payload = otlp_payload(
      otlp_resource_metric(token: @session.route_token, tokens: { input: 0 }, cost_usd: 0.0)
    )

    result = nil
    assert_no_difference("UsageStatistic.count") do
      result = UsageStatisticsService.process(payload.to_json)
    end

    assert_equal :accepted, result.status
    assert_nil @session.reload.usage_statistic
  end

  private

  # Build one OTLP resourceMetrics entry carrying the terminal_session_token on
  # the resource, a claude_code.token.usage sum (one data point per token type),
  # and an optional claude_code.cost.usage sum.
  def otlp_resource_metric(token:, tokens: {}, cost_usd: nil, model: "claude-sonnet-4-6")
    data_points = tokens.map do |type, value|
      {
        "attributes" => [
          { "key" => "type", "value" => { "stringValue" => type.to_s } },
          { "key" => "model", "value" => { "stringValue" => model } }
        ],
        "asInt" => value.to_s
      }
    end

    metrics = []
    metrics << { "name" => "claude_code.token.usage", "sum" => { "dataPoints" => data_points } } if data_points.any?
    unless cost_usd.nil?
      metrics << {
        "name" => "claude_code.cost.usage",
        "sum" => { "dataPoints" => [ { "attributes" => [], "asDouble" => cost_usd } ] }
      }
    end

    {
      "resource" => {
        "attributes" => [ { "key" => "terminal_session_token", "value" => { "stringValue" => token } } ]
      },
      "scopeMetrics" => [ { "metrics" => metrics } ]
    }
  end

  def otlp_payload(*resource_metrics)
    { "resourceMetrics" => resource_metrics }
  end
end
