# frozen_string_literal: true

module WorkflowDrafts
  # Rewrites step specs — snapshot steps or a builder Save's steps, both the
  # shape WorkflowStepSync takes — from one workflow's step ids to another's:
  # the step ids themselves, `depends_on_step_ids`, and the `{{step:…}}` /
  # `{{output:…}}` references in instructions. A step with no counterpart
  # becomes a new one, keyed `new-<its id>` so WorkflowStepSync can resolve
  # dependencies and references to it once it exists.
  class Translation
    # `step_ids`: from step id => to step id.
    # `sub_step_ids`: from sub-step id => [to step id, to sub-step id].
    def initialize(step_ids = {}, sub_step_ids = {})
      @step_ids = step_ids
      @sub_step_ids = sub_step_ids
    end

    # With `preview: true` the result is a snapshot's steps for a diff: a new
    # step or sub-step carries its key as its id and no "key" is added.
    def specs(steps, preview: false)
      keys = steps.to_h { |spec| [ source_key(spec), target_key(spec) ] }
      steps.map do |spec|
        target = mapped(spec["id"])
        key = keys.fetch(source_key(spec))
        translated = spec.merge(
          "id" => target || (key if preview),
          "depends_on_step_ids" => Array(spec["depends_on_step_ids"]).map { |dep| typed(keys.fetch(dep.to_s, dep.to_s)) },
          "instructions" => rewrite(spec["instructions"], keys),
          "sub_steps" => Array(spec["sub_steps"]).map { |sub| sub_step(sub, target, keys, preview) }
        )
        preview ? translated.except("key") : translated.merge("key" => key)
      end
    end

    private

    def mapped(id)
      id.to_s.match?(/\A\d+\z/) ? @step_ids[id.to_i] : nil
    end

    def source_key(spec)
      (spec["key"].presence || spec["id"]).to_s
    end

    def target_key(spec)
      target = mapped(spec["id"])
      return target.to_s if target

      key = source_key(spec)
      key.start_with?("new-") ? key : "new-#{key}"
    end

    def sub_step(sub, target_step_id, keys, preview)
      step_id, id = @sub_step_ids[sub["id"].to_i] if sub["id"].present?
      id = nil unless target_step_id && step_id == target_step_id
      sub.merge(
        "id" => id || ("new-#{sub['id']}" if preview),
        "instructions" => rewrite(sub["instructions"], keys)
      )
    end

    def rewrite(text, keys)
      return text if text.blank?

      InstructionReferences.rewrite(text) do |ref|
        target = ref.valid? && %w[step output].include?(ref.type) && keys[ref.id.to_s]
        next nil unless target

        ref.type == "output" ? "{{output:#{target}:#{ref.name}}}" : "{{step:#{target}}}"
      end
    end

    # A step id is an Integer in a snapshot; a key for a step yet to be made stays a String.
    def typed(key)
      key.match?(/\A\d+\z/) ? key.to_i : key
    end
  end
end
