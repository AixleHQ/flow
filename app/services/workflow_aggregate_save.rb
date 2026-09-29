# frozen_string_literal: true

# Applies the builder's whole-workflow payload (Api::V1::Projects::Workflows::
# AggregatesController). Checked up front, before anything is written, for what
# the step-by-step validations would only catch half-way through: a dependency
# on a step that is not in the payload, or two steps under one key.
class WorkflowAggregateSave
  class Invalid < StandardError; end

  def initialize(workflow, payload)
    @workflow = workflow
    @payload = payload.deep_stringify_keys
    @steps = Array(@payload["steps"])
  end

  def validate!
    keys = @steps.map { |s| (s["key"].presence || s["id"]).to_s }
    raise Invalid, "Every step needs an id or a key" if keys.any?(&:blank?)
    raise Invalid, "Two steps share the key #{keys.tally.find { |_, n| n > 1 }.first}" if keys.uniq.size != keys.size

    live = @workflow.steps.not_deleted.pluck(:id).to_set
    stale = @steps.filter_map { |s| s["id"].presence&.to_i }.reject { |id| live.include?(id) }
    raise Invalid, "Steps #{stale.join(', ')} are no longer in this workflow — reload" if stale.any?

    @steps.each do |step|
      unknown = Array(step["depends_on_step_ids"]).map(&:to_s) - keys
      raise Invalid, "#{step['name']} depends on a step that is not in the workflow" if unknown.any?
    end
    self
  end

  def apply!
    @workflow.assign_attributes(@payload.slice("name", "description"))
    @workflow.config = (@workflow.config || {}).merge(@payload["config"]) if @payload.key?("config")
    @workflow.save!
    WorkflowStepSync.new(@workflow, @steps).sync!
  end
end
