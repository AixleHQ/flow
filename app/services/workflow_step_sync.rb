# frozen_string_literal: true

# Makes a workflow's live steps and sub-steps exactly the given list — the one
# write behind both a version revert (the list is a snapshot) and the builder's
# Save (the list is what the editor holds).
#
# Each step spec is a hash of step columns plus:
#   "id"                  an existing step's id, or nil for a new step
#   "key"                 how other specs name this step in "depends_on_step_ids"
#                         (defaults to "id"; a new step needs one of its own)
#   "sub_steps"           the step's sub-steps, each with "id" nil for a new one
#   "origin_step_id"      with `keep_origins:` only — the step a draft's copy came from,
#                         and "origin_sub_step_id" on its sub-steps
#
# Steps and sub-steps missing from the list are soft-deleted, never removed, so
# every id a version snapshot names keeps its row. The order of writes is chosen
# so no intermediate state trips a constraint: positions are parked clear of the
# unique (workflow_id, position) index, dependencies are cleared before any step
# is validated, then set again in dependency order so a transient cycle is
# never seen by the cycle validation.
class WorkflowStepSync
  STEP_COLUMNS = (Versions::Snapshots::Workflow::STEP_FIELDS + Versions::Snapshots::Workflow::STEP_REFERENCES.keys -
                  %w[id depends_on_step_ids]).freeze
  SUB_STEP_COLUMNS = (Versions::Snapshots::Workflow::SUB_STEP_FIELDS - %w[id]).freeze

  # Ids of rows that still exist, in the given order. A reference to a row that
  # is gone altogether is dropped; an archived one is kept. Integrations are accounts of one
  # tenant: with a `project:`, one it does not own (detached by a project move) is dropped too.
  def self.existing_ids(model_name, ids, project: nil)
    ids = Array(ids).compact_blank.map(&:to_i)
    return [] if ids.empty?

    model = model_name.constantize
    rows = project && model == Integration ? TenantScope.owned(model, project: project) : model
    found = rows.where(id: ids).pluck(:id).to_set
    ids.select { |id| found.include?(id) }
  end

  # `refuse_unknown:` names step lists whose ids of rows that are gone are kept, so the step's own
  # validation refuses them (a person saving an integration list that names none has made a
  # mistake; a revert has not, and drops them).
  def initialize(workflow, specs, keep_origins: false, refuse_unknown: [])
    @workflow = workflow
    @refuse_unknown = refuse_unknown
    @step_columns = keep_origins ? STEP_COLUMNS + %w[origin_step_id] : STEP_COLUMNS
    @sub_step_columns = keep_origins ? SUB_STEP_COLUMNS + %w[origin_sub_step_id] : SUB_STEP_COLUMNS
    @specs = specs.each_with_index.map do |spec, index|
      spec.merge("key" => spec_key(spec), "position" => spec["position"] || (index + 1))
    end
  end

  def sync!
    rows = @workflow.steps.unscope(:order).includes(:sub_steps, :resource_links).lock.to_a.index_by(&:id)
    park_positions(rows.values)
    steps = write_steps(rows)
    key_map = steps.transform_values(&:id)
    rewrite_draft_references(key_map)
    retire_others(rows, key_map)
    write_dependencies(steps, key_map)
    key_map
  end

  private

  def spec_key(spec)
    (spec["key"].presence || spec["id"]).to_s
  end

  def park_positions(rows)
    highest = [ rows.filter_map(&:position).max.to_i, @specs.map { |s| s["position"].to_i }.max.to_i ].max
    offset = highest + rows.size + @specs.size + 1
    rows.each_with_index { |row, index| row.update_column(:position, offset + index) }
  end

  # Every listed step, without its dependencies. A spec naming an id the
  # workflow no longer has (hard-deleted before steps were always soft-deleted)
  # gets a new row.
  def write_steps(rows)
    @specs.each_with_object({}) do |spec, steps|
      step = rows[spec["id"].presence&.to_i] || @workflow.steps.new
      attrs = spec.slice(*@step_columns)
      Versions::Snapshots::Workflow::STEP_REFERENCES.each do |column, model|
        next if !attrs.key?(column) || @refuse_unknown.include?(column)

        attrs[column] = self.class.existing_ids(model, attrs[column], project: @workflow.runner_project)
      end
      attrs["agent_id"] = nil if attrs["agent_id"].present? && !Agent.exists?(attrs["agent_id"])
      step.assign_attributes(attrs.merge("depends_on_step_ids" => [], "deleted_at" => nil))
      step.save!
      write_sub_steps(step, Array(spec["sub_steps"]))
      steps[spec["key"]] = step
    end
  end

  # A reference to a step created by this same request names it by its draft
  # key (`{{step:new-2}}`); now that it has an id, the reference carries that.
  def rewrite_draft_references(key_map)
    @specs.each do |spec|
      text = spec["instructions"].to_s
      next unless text.include?(":new-")

      rewritten = InstructionReferences.rewrite(text) do |ref|
        id = ref.valid? && ref.id.is_a?(String) && key_map[ref.id]
        next nil unless id && ref.id.start_with?("new-")

        ref.type == "output" ? "{{output:#{id}:#{ref.name}}}" : "{{step:#{id}}}"
      end
      Step.where(id: key_map.fetch(spec["key"])).update_all(instructions: rewritten) if rewritten != text
    end
  end

  def retire_others(rows, key_map)
    kept = key_map.values.to_set
    next_free = @specs.map { |s| s["position"].to_i }.max.to_i
    rows.each_value do |row|
      next if kept.include?(row.id)

      next_free += 1
      row.update_columns(position: next_free, depends_on_step_ids: [], deleted_at: row.deleted_at || Time.current)
    end
  end

  # Only depends_on_step_ids may be written here: the in-memory instructions can
  # still hold draft keys that rewrite_draft_references replaced in the database.
  def write_dependencies(steps, key_map)
    by_key = @specs.index_by { |s| s["key"] }
    in_dependency_order(by_key).each do |key|
      deps = Array(by_key[key]["depends_on_step_ids"]).filter_map { |dep| key_map[dep.to_s] }
      next if deps.empty?

      steps.fetch(key).update!(depends_on_step_ids: deps)
    end
  end

  def in_dependency_order(by_key)
    order = []
    visiting = Set.new
    visit = lambda do |key|
      return if order.include?(key) || visiting.include?(key) || !by_key.key?(key)

      visiting << key
      Array(by_key[key]["depends_on_step_ids"]).each { |dep| visit.call(dep.to_s) }
      visiting.delete(key)
      order << key
    end
    by_key.each_key { |key| visit.call(key) }
    order
  end

  def write_sub_steps(step, specs)
    rows = step.sub_steps.to_a.index_by(&:id)
    kept = specs.each_with_index.map do |spec, index|
      sub = rows[spec["id"].presence&.to_i] || step.sub_steps.new
      attrs = spec.slice(*@sub_step_columns)
      attrs["position"] ||= index + 1
      sub.assign_attributes(attrs.merge("deleted_at" => nil))
      sub.save!
      sub.id
    end
    rows.each_value do |row|
      row.update_column(:deleted_at, Time.current) if !kept.include?(row.id) && row.deleted_at.nil?
    end
  end
end
