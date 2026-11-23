# frozen_string_literal: true

# Workflow drafts (docs/design/workflow-drafts.md). A draft is a hidden copy of a
# workflow in the same project: it is edited through the same endpoints and tools
# as any workflow and test-run through the normal runtime, while triggers and
# columns keep running the original. Applying it writes it onto the original
# through the builder's own Save, as one new version, and closes it.
module WorkflowDrafts
  class Error < StandardError; end

  # The original changed after the draft was made. Applying would also undo those
  # changes, so the caller asks before passing `overwrite: true`.
  class LiveChanged < Error
    attr_reader :base_version, :live_version

    def initialize(base_version, live_version)
      @base_version = base_version
      @live_version = live_version
      super("The live workflow changed after this draft was made (v#{base_version} → v#{live_version}). " \
            "Applying the draft replaces those changes too.")
    end
  end

  module_function

  # The workflow's open draft, made from its current state when there is none.
  # `aggregate` is a builder Save payload, written in the original's step ids,
  # that becomes the new draft's first change (the builder's "Save as draft").
  def open!(workflow, actor:, aggregate: nil)
    raise Error, "A draft cannot have a draft" if workflow.draft?
    raise Error, "Archived workflows cannot have a draft" if workflow.archived?
    raise Error, "Only a project workflow can have a draft" unless workflow.scope_type == "Project"

    Workflow.transaction do
      workflow.lock!
      draft = workflow.open_draft
      raise Error, "This workflow already has a draft — open it instead" if draft && aggregate

      draft ||= create!(workflow, actor)
      save_aggregate!(draft, aggregate, actor) if aggregate
      draft
    end
  end

  # Writes the draft onto the workflow it is a draft of and closes it. Returns the
  # workflow's new version, or nil when the draft changed nothing.
  def apply!(draft, actor:, overwrite: false)
    workflow = open_original!(draft)
    Workflow.transaction do
      workflow.lock!
      unless overwrite || workflow.current_version_number == draft.draft_base_version
        raise LiveChanged.new(draft.draft_base_version, workflow.current_version_number)
      end

      payload = apply_payload(draft, workflow)
      WorkflowAggregateSave.new(workflow, payload).validate!
      metadata = { "applied_from_draft_id" => draft.id, "draft_version_number" => draft.current_version_number }
      version = Versions.save!(workflow, actor: actor, metadata: metadata) do
        WorkflowAggregateSave.new(workflow, payload).apply!
      end
      close!(draft, actor, "applied_as_version_number" => workflow.current_version_number)
      version
    end
  end

  def discard!(draft, actor:)
    open_original!(draft)
    close!(draft, actor, "discarded" => true)
  end

  # What applying would do: the original as it is now, and the draft written in
  # the original's step ids — the two sides of a version diff. A step the draft
  # added carries "new-<id>" for an id, so it matches nothing on the live side.
  def changes(draft)
    workflow = open_original!(draft)
    live = Versions::Snapshot.dump(workflow)
    proposed = Versions::Snapshot.dump(draft)
    proposed["steps"] = to_original(draft, workflow).specs(proposed["steps"], preview: true)
    {
      live: live,
      draft: proposed,
      live_version_number: workflow.current_version_number,
      base_version_number: draft.draft_base_version,
      draft_version_number: draft.current_version_number,
      references: Versions::ReferenceNames.for_snapshots([ live, proposed ], workflow: workflow)
    }
  end

  def open_original!(draft)
    raise Error, "This is not a draft" unless draft.draft?
    raise Error, "This draft was already applied or discarded" if draft.archived?

    draft.draft_of
  end

  def create!(workflow, actor)
    Versions.ensure_baseline!(workflow)
    live = Versions::Snapshot.dump(workflow)
    draft = workflow.scope.workflows.new(
      draft_of: workflow, draft_base_version: workflow.current_version_number,
      name: workflow.name, description: workflow.description, runner_id: workflow.runner_id
    )
    draft.merge_config(workflow.linked_config)
    specs = Translation.new.specs(live["steps"]).zip(live["steps"]).map do |spec, step|
      sub_steps = spec["sub_steps"].zip(step["sub_steps"]).map { |sub, origin| sub.merge("origin_sub_step_id" => origin["id"]) }
      spec.merge("origin_step_id" => step["id"], "sub_steps" => sub_steps)
    end
    Versions.save!(draft, actor: actor, metadata: { "draft_of_id" => workflow.id }) do
      draft.save!
      WorkflowStepSync.new(draft, specs, keep_origins: true).sync!
    end
    draft
  end

  def save_aggregate!(draft, aggregate, actor)
    aggregate = aggregate.deep_stringify_keys
    steps = draft.steps.not_deleted.where.not(origin_step_id: nil)
    step_ids = steps.pluck(:origin_step_id, :id).to_h
    sub_step_ids = SubStep.where(step_id: steps.select(:id), deleted_at: nil).where.not(origin_sub_step_id: nil)
                          .pluck(:origin_sub_step_id, :step_id, :id).to_h { |origin, step_id, id| [ origin, [ step_id, id ] ] }
    payload = aggregate.merge("steps" => Translation.new(step_ids, sub_step_ids).specs(Array(aggregate["steps"])))
    WorkflowAggregateSave.new(draft, payload).validate!
    Versions.save!(draft, actor: actor) { WorkflowAggregateSave.new(draft, payload).apply! }
  end

  def apply_payload(draft, workflow)
    snapshot = Versions::Snapshot.dump(draft)
    {
      "name" => snapshot["name"], "description" => snapshot["description"], "runner_id" => draft.runner_id,
      "config" => draft.linked_config, "steps" => to_original(draft, workflow).specs(snapshot["steps"])
    }
  end

  # Only steps the original still has map back; one deleted there since the
  # draft was made comes back as a new step.
  def to_original(draft, workflow)
    live_step_ids = workflow.steps.not_deleted.pluck(:id)
    step_ids = draft.steps.not_deleted.where(origin_step_id: live_step_ids).pluck(:id, :origin_step_id).to_h
    origin_steps = SubStep.where(step_id: step_ids.values).pluck(:id, :step_id).to_h
    sub_step_ids = SubStep.where(step_id: step_ids.keys, deleted_at: nil, origin_sub_step_id: origin_steps.keys)
                          .pluck(:id, :origin_sub_step_id).to_h { |id, origin| [ id, [ origin_steps[origin], origin ] ] }
    Translation.new(step_ids, sub_step_ids)
  end

  # Unlike archiving a workflow, closing a draft does not wait for its test runs to end: they keep
  # reading the draft's rows, which stay.
  def close!(draft, actor, metadata)
    Versions.record_event!(draft, "archived", actor, nil, metadata: metadata) do
      draft.update_columns(deleted_at: Time.current, updated_at: Time.current)
    end
  end

  private_class_method :open_original!, :create!, :save_aggregate!, :apply_payload, :to_original, :close!
end
