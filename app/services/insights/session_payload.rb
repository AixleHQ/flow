# frozen_string_literal: true

module Insights
  # A session's records as OTLP/HTTP JSON ExportLogsServiceRequests
  # (docs/design/insights-usage-export.md §7): one ResourceLogs per request carrying the
  # session's context, at most CHUNK records each — its LLM calls, and its prompts and tool
  # calls when the project shares them.
  class SessionPayload
    CHUNK = 1_000
    SCOPE = "aixle_flow.export"

    def initialize(terminal_session)
      @session = terminal_session
      @project = terminal_session.project
    end

    def records
      @records ||= begin
        calls = LlmCall.where(terminal_session_id: @session.id).to_a.map { |call| [ call.occurred_at, call_record(call) ] }
        activity = @project&.shares_prompts_with_insights? ? activity_records : []
        (calls + activity).sort_by(&:first).map(&:last)
      end
    end

    def chunks(size = CHUNK)
      records.each_slice(size).map { |slice| request(slice) }
    end

    def request(log_records)
      {
        "resourceLogs" => [ {
          "resource" => { "attributes" => attributes(resource_attributes) },
          "scopeLogs" => [ { "scope" => { "name" => SCOPE }, "logRecords" => log_records } ]
        } ]
      }
    end

    private

    def activity_records
      prompts = AgentPrompt.where(terminal_session_id: @session.id).map { |prompt| [ prompt.occurred_at, prompt_record(prompt) ] }
      tools = AgentToolCall.where(terminal_session_id: @session.id).map { |call| [ call.occurred_at, tool_record(call) ] }
      prompts + tools
    end

    def resource_attributes
      settings = @project&.insights_settings || {}
      repository = settings["project_id"].blank? && single_repository_url
      {
        "service.name" => "aixle-flow",
        "service.version" => Settings.app.version.to_s,
        "aixle_flow.company.id" => @session.company_id || @project&.company_id,
        "aixle_flow.project.id" => @project&.id,
        "aixle_flow.project.name" => @project&.name,
        "aixle_flow.session.id" => @session.id,
        "aixle_flow.session.type" => @session.session_type,
        "aixle_flow.workflow_run.id" => @session.step_run&.workflow_run_id,
        "aixle_flow.agent.type" => @session.agent_type,
        "user.email" => @session.user&.email,
        "insights.project.id" => settings["project_id"].presence,
        "vcs.repository.url.full" => repository.presence
      }
    end

    # Without userinfo: Azure DevOps clone URLs carry the organization there, and nothing
    # in a URL's credential part is Insights' to see.
    def single_repository_url
      urls = @project&.repositories&.limit(2)&.map(&:clone_url)
      return nil unless urls&.size == 1

      URI.parse(urls.first).to_s.sub(%r{\A([a-z][a-z0-9+.-]*://)[^/@]*@}i, '\1')
    rescue URI::InvalidURIError
      nil
    end

    def call_record(call)
      log_record(call.occurred_at, {
        "event.name" => "aixle_flow.llm_call",
        "aixle_flow.llm_call.id" => call.uid,
        "aixle_flow.step_run.id" => call.step_run_id,
        "gen_ai.provider.name" => call.provider,
        "gen_ai.request.model" => call.model,
        "aixle_flow.usage.input_tokens" => call.input_tokens,
        "aixle_flow.usage.output_tokens" => call.output_tokens,
        "aixle_flow.usage.cache_read_tokens" => call.cache_read_tokens,
        "aixle_flow.usage.cache_write_tokens" => call.cache_write_tokens,
        "aixle_flow.cost.usd" => call.total_cents_precise && (call.total_cents_precise.to_f / 100.0),
        "aixle_flow.cost.basis" => call.cost_basis,
        "aixle_flow.granularity" => call.granularity,
        "aixle_flow.source" => call.source,
        "aixle_flow.duration_ms" => call.duration_ms,
        "aixle_flow.prompt.ref" => call.prompt_ref
      })
    end

    def prompt_record(prompt)
      log_record(prompt.occurred_at, {
        "event.name" => "aixle_flow.prompt",
        "aixle_flow.prompt.id" => prompt.uid,
        "aixle_flow.prompt.source" => prompt.source,
        "aixle_flow.prompt.length" => prompt.text_length,
        "aixle_flow.prompt.truncated" => prompt.truncated,
        "aixle_flow.prompt.ref" => prompt.prompt_ref,
        "aixle_flow.step_run.id" => prompt.step_run_id
      }, body: prompt.text)
    end

    def tool_record(call)
      log_record(call.occurred_at, {
        "event.name" => "aixle_flow.tool_call",
        "aixle_flow.tool_call.id" => call.uid,
        "gen_ai.tool.name" => call.tool_name,
        "aixle_flow.tool.mcp_server" => call.mcp_server,
        "aixle_flow.tool.arguments" => call.arguments&.to_json,
        "aixle_flow.tool.success" => call.success,
        "aixle_flow.tool.error" => call.error,
        "aixle_flow.duration_ms" => call.duration_ms,
        "aixle_flow.prompt.ref" => call.prompt_ref,
        "aixle_flow.step_run.id" => call.step_run_id
      })
    end

    def log_record(time, attrs, body: nil)
      record = { "timeUnixNano" => (time.to_r * 1_000_000_000).to_i.to_s, "attributes" => attributes(attrs) }
      record["body"] = { "stringValue" => body } if body
      record
    end

    # Unknown values are left out, never sent as zero or empty (§7). OTLP JSON writes an
    # int64 as a string.
    def attributes(hash)
      hash.filter_map do |key, value|
        next if value.nil?

        { "key" => key, "value" => otlp_value(value) }
      end
    end

    def otlp_value(value)
      case value
      when true, false then { "boolValue" => value }
      when Integer then { "intValue" => value.to_s }
      when Float, BigDecimal then { "doubleValue" => value.to_f }
      else { "stringValue" => value.to_s }
      end
    end
  end
end
