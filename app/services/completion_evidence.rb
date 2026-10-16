# frozen_string_literal: true

class CompletionEvidence
  Result = Struct.new(:errors, :receipts, keyword_init: true) do
    def valid? = errors.empty?
  end

  def initialize(session)
    @session = session
  end

  def required?
    @session.metadata.to_h["completion_evidence_required"] == true ||
      @session.step_run&.workflow_run&.workflow&.config.to_h["completion_evidence_required"] == true
  end

  def validate(ids)
    ids = [] if ids.nil?
    unless ids.is_a?(Array) && ids.size <= 20 && ids.all? { |id| id.is_a?(String) && id.present? && id.length <= 128 }
      return invalid("Completion evidence must contain at most 20 non-empty execution ID strings")
    end
    return invalid("Completion evidence is required: supply evidence_execution_ids") if required? && ids.empty?

    ids = ids.uniq
    executions = ToolResult.where(terminal_session_id: @session.id, execution_id: ids, state: "completed", exit_code: 0)
                          .includes(:tool).index_by(&:execution_id)
    unless executions.size == ids.size
      return invalid("Completion evidence must reference successful completed tool executions from the current session")
    end

    receipts = ids.map do |id|
      execution = executions.fetch(id)
      { "execution_id" => id, "tool_id" => execution.tool_id, "tool_name" => execution.tool.name,
        "exit_code" => execution.exit_code, "verified_at" => Time.current.iso8601 }
    end
    Result.new(errors: [], receipts: receipts)
  end

  private

  def invalid(message)
    Result.new(errors: [ message ], receipts: [])
  end
end
