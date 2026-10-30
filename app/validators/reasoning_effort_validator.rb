# frozen_string_literal: true

# A reasoning-effort level must be one the record's runtime takes for its model, as
# config/agent_runtimes.json lists them (AgentRuntime#reasoning_effort_levels):
#
#   validates :reasoning_effort, inclusion: { in: ->(_) { AgentRuntime.reasoning_effort_levels } }, allow_nil: true
#   validates :reasoning_effort, reasoning_effort: { runtime: :required_agent_runtime, model: :preferred_model }
#
# The inclusion check refuses a word that is no level at all; this one, a level the
# runtime does not take for the model. `runtime:` / `model:` name the record's methods
# that return them.
#
# A level and its model are always kept consistent, so a level needs both an
# explicitly chosen runtime and an explicitly chosen model: without either there is
# nothing to check it against (the credential's default model can change at any time),
# and the record is invalid. Clearing the model or the runtime while a level is set is
# refused the same way, so a caller clears the level with them.
class ReasoningEffortValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    level = value.to_s
    # Not a level at all: the attribute's inclusion validation reports that.
    return unless AgentRuntime.reasoning_effort_levels.include?(level)

    runtime_id = record.send(options.fetch(:runtime)).presence
    model = record.send(options.fetch(:model)).presence
    return record.errors.add(attribute, "needs an explicitly chosen runtime") if runtime_id.nil?
    return record.errors.add(attribute, "needs an explicitly chosen model") if model.nil?

    runtime = AgentRuntime.all.find { |r| r.id == runtime_id.to_s }
    return if runtime.nil? # the runtime's own inclusion validation reports it
    return if runtime.reasoning_effort?(level, model)

    record.errors.add(attribute, unsupported_message(runtime, level, model))
  end

  private

  def unsupported_message(runtime, level, model)
    levels = runtime.reasoning_effort_levels(model)
    target = "#{runtime.id} with model #{model}"
    return "is not available for #{target}" if levels.empty?

    "#{level} is not available for #{target} (choose one of: #{levels.join(', ')})"
  end
end
