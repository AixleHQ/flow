# frozen_string_literal: true

class LlmCallsQuery
  SORT_OPTIONS = {
    "occurred_at_desc" => { occurred_at: :desc },
    "cost_desc"        => { total_cents_precise: :desc }
  }.freeze
  DEFAULT_SORT = "occurred_at_desc"

  def initialize(workflow_run: nil, terminal_session: nil,
                 step_run_id: nil, model: nil, date_from: nil, date_to: nil,
                 sort: nil)
    raise ArgumentError, "pass workflow_run: or terminal_session:" if workflow_run.nil? && terminal_session.nil?

    @workflow_run     = workflow_run
    @terminal_session = terminal_session
    @step_run_id      = step_run_id.presence
    @model            = model.presence
    @date_from        = date_from.presence
    @date_to          = date_to.presence
    @sort             = SORT_OPTIONS.key?(sort) ? sort : DEFAULT_SORT
  end

  def scope
    s = root_scope
    s = s.where(step_run_id: @step_run_id) if @step_run_id
    s = s.where(model: @model)             if @model
    s = s.where("occurred_at >= ?", @date_from) if @date_from
    s = s.where("occurred_at <= ?", @date_to)   if @date_to
    s.order(SORT_OPTIONS[@sort])
  end

  private

  def root_scope
    if @workflow_run
      LlmCall.for_workflow_run(@workflow_run.id)
    else
      LlmCall.for_session(@terminal_session.id)
    end
  end
end
