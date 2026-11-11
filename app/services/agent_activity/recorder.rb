# frozen_string_literal: true

module AgentActivity
  # Writes the prompts and tool calls an adapter read out of a runtime's telemetry, for a
  # project that shares prompts with Aixle Insights (docs/design/insights-usage-export.md
  # §3a). Text and arguments are masked against the session's known secrets and capped,
  # and every row is keyed by the runtime's own id, so a batch delivered twice is written
  # once. Assistant replies and tool outputs never reach this class.
  class Recorder
    PROMPT_LIMIT = 64.kilobytes
    ARGUMENT_STRING_LIMIT = 8.kilobytes
    ARGUMENTS_LIMIT = 32.kilobytes
    ERROR_LIMIT = 500
    MCP_TOOL = /\Amcp__(?<server>.+?)__.+\z/

    Prompt = Struct.new(:key, :occurred_at, :text, :prompt_ref, :source, keyword_init: true)
    ToolCall = Struct.new(:key, :occurred_at, :tool_name, :arguments, :success, :error, :duration_ms,
                          :prompt_ref, :source, keyword_init: true)

    def self.enabled_for?(terminal_session)
      terminal_session.project&.shares_prompts_with_insights? || false
    end

    def self.record(terminal_session, prompts: [], tool_calls: [])
      new(terminal_session).record(prompts: prompts, tool_calls: tool_calls)
    end

    # The session's own prompt as Flow rendered it, for a runtime that reports none.
    def self.record_initial_prompt(terminal_session)
      text = terminal_session.initial_prompt
      return 0 if text.blank?

      record(terminal_session, prompts: [
        Prompt.new(key: "initial_prompt", occurred_at: terminal_session.started_at || terminal_session.created_at,
                   text: text, source: "flow")
      ])
    end

    def initialize(terminal_session)
      @session = terminal_session
    end

    def record(prompts:, tool_calls:)
      return 0 unless self.class.enabled_for?(@session)

      written = insert(AgentPrompt, prompts.map { |prompt| prompt_row(prompt) })
      written + insert(AgentToolCall, tool_calls.map { |call| tool_call_row(call) })
    end

    private

    def insert(model, rows)
      return 0 if rows.empty?

      model.insert_all(rows, unique_by: %i[terminal_session_id source_key], returning: false)
      rows.size
    end

    def prompt_row(prompt)
      text = prompt.text.to_s
      masked = redactor.call(text)
      capped = cap(masked, PROMPT_LIMIT)
      base_row(prompt).merge(text: capped, text_length: text.length, truncated: capped.bytesize < masked.bytesize)
    end

    def tool_call_row(call)
      base_row(call).merge(
        tool_name: call.tool_name.to_s,
        mcp_server: call.tool_name.to_s[MCP_TOOL, :server],
        arguments: arguments(call.arguments),
        success: call.success,
        error: call.error.presence && cap(redactor.call(call.error.to_s), ERROR_LIMIT),
        duration_ms: call.duration_ms&.to_i
      )
    end

    def base_row(entry)
      now = Time.current
      {
        terminal_session_id: @session.id,
        workflow_run_id: step_run&.workflow_run_id,
        step_run_id: step_run&.id,
        source_key: entry.key.to_s,
        source: entry.source,
        occurred_at: entry.occurred_at || now,
        prompt_ref: entry.prompt_ref,
        created_at: now,
        updated_at: now
      }
    end

    # Each string masked and capped on its own; a whole that is still too large is kept as
    # its JSON text, cut, so the row says what was called without carrying a file's worth.
    def arguments(raw)
      return nil if raw.nil?

      cleaned = mask_strings(raw)
      json = cleaned.to_json
      return cleaned if json.bytesize <= ARGUMENTS_LIMIT

      { "truncated" => true, "json" => cap(json, ARGUMENTS_LIMIT) }
    end

    def mask_strings(value)
      case value
      when Hash then value.to_h { |key, inner| [ key.to_s, mask_strings(inner) ] }
      when Array then value.map { |inner| mask_strings(inner) }
      when String then cap(redactor.call(value), ARGUMENT_STRING_LIMIT)
      else value
      end
    end

    def cap(text, bytes)
      return text if text.bytesize <= bytes

      text.byteslice(0, bytes).scrub("")
    end

    def redactor
      @redactor ||= Sessions::SecretRedactor.for_session(@session)
    end

    def step_run
      return @step_run if defined?(@step_run)

      @step_run = @session.step_run
    end
  end
end
