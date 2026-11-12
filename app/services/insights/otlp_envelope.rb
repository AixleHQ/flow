# frozen_string_literal: true

require "digest"

module Insights
  # An agent's OTLP request, made fit to leave Flow (docs/design/insights-otlp-relay.md §4).
  # The records stay as the agent wrote them, with three exceptions:
  #
  # - The session's token and key are removed wherever they sit. The key proves a batch to
  #   Flow's ingest; outside Flow it is a credential for that session's usage.
  # - Each resource names its person, project and session from Flow's records, never from
  #   what the container set: the agent controls its own environment.
  # - Known secrets of the session are masked, and each log record carries
  #   `aixle_flow.record.id`, a hash of its content, so a re-send — ours or the agent SDK's —
  #   arrives with the same id.
  class OtlpEnvelope
    SIGNALS = {
      "resourceLogs" => { signal: "logs", scopes: "scopeLogs", items: "logRecords" },
      "resourceMetrics" => { signal: "metrics", scopes: "scopeMetrics", items: "metrics" },
      "resourceSpans" => { signal: "traces", scopes: "scopeSpans", items: "spans" }
    }.freeze
    KEYS = SIGNALS.to_h { |key, shape| [ shape[:signal], key ] }.freeze
    SESSION_ATTRIBUTES = [ "terminal_session_token", UsageStatistics::SessionKey::ATTRIBUTE ].freeze
    RECORD_ID = "aixle_flow.record.id"
    FLOW_OWNED = %w[user.email insights.project.id vcs.repository.url.full].freeze
    FLOW_PREFIX = "aixle_flow."
    DATA_POINT_KINDS = %w[gauge sum histogram exponentialHistogram summary].freeze

    Part = Struct.new(:session, :signal, :request, :record_count, keyword_init: true)

    # The request split by the session each resource proves it belongs to (by its token and
    # key, as UsageStatisticsService checks them). A resource that proves none is dropped.
    def self.parts(payload, sessions_by_token)
      new(payload, sessions_by_token).parts
    end

    def initialize(payload, sessions_by_token)
      @payload = payload
      @sessions = sessions_by_token
    end

    def parts
      SIGNALS.flat_map do |key, shape|
        Array(@payload[key]).group_by { |resource| owner(resource, shape) }.filter_map do |token, resources|
          session = token && @sessions[token]
          next unless session

          resources = resources.map { |resource| seal(resource, session, shape) }
          Part.new(session: session, signal: shape[:signal], request: { key => resources },
                   record_count: count(resources, shape))
        end
      end
    end

    private

    def owner(resource, shape)
      keyed = keyed_token(resource.dig("resource", "attributes"))
      return keyed if keyed

      tokens = attribute_sets(resource, shape).filter_map { |attrs| keyed_token(attrs) }.uniq
      tokens.first if tokens.one?
    end

    def keyed_token(attrs)
      return unless attrs.is_a?(Array)

      token = string_value(attrs, "terminal_session_token")
      token if UsageStatistics::SessionKey.valid?(token, string_value(attrs, UsageStatistics::SessionKey::ATTRIBUTE))
    end

    def attribute_sets(resource, shape)
      items(resource, shape).flat_map do |item|
        next [ item["attributes"] ] unless shape[:signal] == "metrics"

        DATA_POINT_KINDS.flat_map { |kind| Array(item.dig(kind, "dataPoints")).map { |point| point["attributes"] } }
      end
    end

    def items(resource, shape)
      Array(resource[shape[:scopes]]).flat_map { |scope| Array(scope[shape[:items]]) }
    end

    def count(resources, shape)
      resources.sum { |resource| items(resource, shape).size }
    end

    def seal(resource, session, shape)
      sealed = mask(strip(resource), redactor_for(session))
      sealed["resource"] = sealed.fetch("resource", {})
                                 .merge("attributes" => flow_attributes(sealed.dig("resource", "attributes"), session))
      stamp_record_ids(sealed, session, shape) if shape[:signal] == "logs"
      sealed
    end

    # Every attribute list, at any depth (resource, record, data point, span event).
    def strip(node)
      case node
      when Hash
        node.to_h do |key, value|
          value = value.reject { |kv| kv.is_a?(Hash) && SESSION_ATTRIBUTES.include?(kv["key"]) } if key == "attributes" && value.is_a?(Array)
          [ key, strip(value) ]
        end
      when Array then node.map { |value| strip(value) }
      else node
      end
    end

    def mask(node, redactor)
      return node unless redactor.any?

      case node
      when Hash then node.transform_values { |value| mask(value, redactor) }
      when Array then node.map { |value| mask(value, redactor) }
      when String then redactor.call(node)
      else node
      end
    end

    def flow_attributes(attrs, session)
      kept = Array(attrs).reject do |kv|
        key = kv.is_a?(Hash) ? kv["key"].to_s : ""
        key.start_with?(FLOW_PREFIX) || FLOW_OWNED.include?(key)
      end
      kept + Metadata.new(session).attributes
    end

    def stamp_record_ids(resource, session, shape)
      Array(resource[shape[:scopes]]).each do |scope|
        Array(scope[shape[:items]]).each do |record|
          digest = Digest::SHA256.hexdigest("#{session.id}\0#{record.to_json}")[0, 32]
          record["attributes"] = Array(record["attributes"]) + [ { "key" => RECORD_ID, "value" => { "stringValue" => digest } } ]
        end
      end
    end

    def redactor_for(session)
      @redactors ||= {}
      @redactors[session.id] ||= Sessions::SecretRedactor.for_session(session)
    end

    def string_value(attrs, key)
      pair = attrs.find { |kv| kv.is_a?(Hash) && kv["key"] == key }
      value = pair&.dig("value") || {}
      (value["stringValue"] || value["intValue"])&.to_s
    end
  end
end
