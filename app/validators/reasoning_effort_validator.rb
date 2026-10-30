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
# A level applies only to a model chosen explicitly. With the model left on the
# default there is nothing to check it against: the credential's default model can
# change at any time, so the launch ignores the level instead
# (TerminalSession#launch_reasoning_effort), and this validation passes.
#
# A record without a runtime passes with `allow_unknown_runtime: true`, for a step
# that leaves the runtime to resolution: the launch drops a level the resolved CLI does
# not take. Without that option a missing runtime is an error.
class ReasoningEffortValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    level = value.to_s
    # Not a level at all: the attribute's inclusion validation reports that.
    return unless AgentRuntime.reasoning_effort_levels.include?(level)

    model = record.send(options.fetch(:model)).presence
    return if model.nil? # ignored at launch: no model was chosen to apply it to

    runtime_id = record.send(options.fetch(:runtime)).presence
    if runtime_id.nil?
      record.errors.add(attribute, "needs a runtime to choose a level for") unless options[:allow_unknown_runtime]
      return
    end

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
