# frozen_string_literal: true

require "set"

class UsageStatisticsService
  Result = Struct.new(:status, :error, keyword_init: true)

  def self.process(raw_body)
    new(raw_body).process
  end

  def initialize(raw_body)
    @raw_body = raw_body
  end

  def process
    payload = parse_json(@raw_body)
    return Result.new(status: :bad_request, error: "Invalid JSON payload") unless payload

    tokens = extract_terminal_session_tokens(payload)
    return Result.new(status: :accepted) if tokens.empty?

    sessions = find_sessions(tokens)
    return Result.new(status: :not_found, error: "Terminal session not found") unless sessions

    persisted = false
    sessions.each_value do |terminal_session|
      adapter = adapter_for(terminal_session)
      result = adapter.ingest_usage(payload, terminal_session)
      persisted ||= (result == :ok)
    end

    persisted ? Result.new(status: :ok) : Result.new(status: :accepted)
  rescue ArgumentError => e
    Result.new(status: :bad_request, error: e.message)
  rescue StandardError => e
    Rails.logger.error("UsageStatisticsService error: #{e.message}")
    Result.new(status: :error, error: "Failed to persist usage")
  end

  private

  def parse_json(raw_body)
    body = raw_body.to_s
    return nil if body.blank?

    JSON.parse(body)
  rescue JSON::ParserError
    nil
  end

  def extract_terminal_session_tokens(payload)
    tokens = Set.new

    resource_metrics = payload["resourceMetrics"] || []
    resource_metrics.each do |resource_metric|
      resource_attrs = resource_metric.dig("resource", "attributes") || []
      scope_metrics = resource_metric["scopeMetrics"] || []

      scope_metrics.each do |scope_metric|
        metrics = scope_metric["metrics"] || []
        metrics.each do |metric|
          data_points = extract_data_points(metric)
          data_points.each do |data_point|
            token = extract_terminal_session_token(data_point["attributes"] || [], resource_attrs)
            tokens.add(token) if token.present?
          end
        end
      end
    end

    resource_logs = payload["resourceLogs"] || []
    resource_logs.each do |resource_log|
      resource_attrs = resource_log.dig("resource", "attributes") || []
      scope_logs = resource_log["scopeLogs"] || []

      scope_logs.each do |scope_log|
        log_records = scope_log["logRecords"] || []
        log_records.each do |log_record|
          token = extract_terminal_session_token(log_record["attributes"] || [], resource_attrs)
          tokens.add(token) if token.present?
        end
      end
    end

    tokens.to_a
  end

  def extract_data_points(metric)
    sum = metric["sum"]
    return sum["dataPoints"] if sum.is_a?(Hash) && sum["dataPoints"].is_a?(Array)

    gauge = metric["gauge"]
    return gauge["dataPoints"] if gauge.is_a?(Hash) && gauge["dataPoints"].is_a?(Array)

    []
  end

  def extract_terminal_session_token(attrs, resource_attrs)
    value = attribute_value(attrs, "terminal_session_token")
    value ||= attribute_value(resource_attrs, "terminal_session_token")

    normalize_terminal_session_token(value)
  end

  def attribute_value(attrs, key)
    attrs.each do |kv|
      next unless kv["key"] == key

      value = kv["value"] || {}
      return value["stringValue"].to_s if value.key?("stringValue")
      return value["intValue"].to_s if value.key?("intValue")
    end

    nil
  end

  def normalize_terminal_session_token(raw)
    token = raw.to_s.strip
    return nil if token.blank?

    token
  end

  def find_sessions(tokens)
    sessions = {}

    tokens.each do |token|
      terminal_session = TerminalSession.lock.find_by(route_token: token)
      return nil unless terminal_session

      sessions[token] = terminal_session
    end

    sessions
  end

  def adapter_for(terminal_session)
    AgentCredentialsService.for(terminal_session.agent_type).adapter
  end
end
