# frozen_string_literal: true

# A reasoning-effort level can be set only when both the runtime and the model are
# chosen explicitly, and it must be one that this runtime takes for this model, as
# config/agent_runtimes.json lists them (AgentRuntime#reasoning_effort_levels):
#
#   validates :reasoning_effort, reasoning_effort: { runtime: :required_agent_runtime, model: :preferred_model }
#
# `runtime:` / `model:` name the record's methods that return them. Clearing the model
# or the runtime while a level is set is refused the same way, so a caller clears the
# level with them.
class ReasoningEffortValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    runtime_id = record.send(options.fetch(:runtime)).presence
    model = record.send(options.fetch(:model)).presence
    return record.errors.add(attribute, "needs an explicitly chosen runtime") if runtime_id.nil?
    return record.errors.add(attribute, "needs an explicitly chosen model") if model.nil?

    runtime = AgentRuntime.all.find { |r| r.id == runtime_id.to_s }
    return if runtime.nil? # the runtime's own inclusion validation reports it
    return if runtime.reasoning_effort?(value, model)

    record.errors.add(attribute, unsupported_message(runtime, value.to_s, model))
  end

  private

  def unsupported_message(runtime, level, model)
    levels = runtime.reasoning_effort_levels(model)
    target = "#{runtime.id} with model #{model}"
    return "is not available for #{target}" if levels.empty?

    "#{level} is not available for #{target} (choose one of: #{levels.join(', ')})"
  end
end
