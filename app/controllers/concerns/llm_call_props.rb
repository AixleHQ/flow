# frozen_string_literal: true

# The LLM calls list on the session and run pages. Callers pass it as a lambda: a live
# update reloads only the props it names, and a run can carry thousands of calls, so the
# list is built only when the page asks for it.
module LlmCallProps
  private

  def llm_call_props(scope)
    scope.includes(step_run: :step).order(occurred_at: :desc).map { |call| LlmCallResource.new(call).to_h }
  end
end
