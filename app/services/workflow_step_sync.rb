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
#
# Steps and sub-steps missing from the list are soft-deleted, never removed, so
# every id a version snapshot names keeps its row. The order of writes is chosen
# so no intermediate state trips a constraint: positions are parked clear of the
# unique (workflow_id, position) index, dependencies are cleared before any step
# is validated, then set again in dependency order so a transient cycle is
# never seen by the cycle validation.
class WorkflowStepSync
  STEP_COLUMNS = (Versions::Snapshots::Workflow::STEP_FIELDS - %w[id depends_on_step_ids]).freeze
  SUB_STEP_COLUMNS = (Versions::Snapshots::Workflow::SUB_STEP_FIELDS - %w[id]).freeze

  # Ids of rows that still exist, in the given order. A reference to a row that
  # is gone altogether is dropped; an archived one is kept.
  def self.existing_ids(model_name, ids)
    ids = Array(ids).compact_blank.map(&:to_i)
    return [] if ids.empty?

    found = model_name.constantize.where(id: ids).pluck(:id).to_set
    ids.select { |id| found.include?(id) }
  end

  def initialize(workflow, specs)
    @workflow = workflow
    @specs = specs.each_with_index.map do |spec, index|
      spec.merge("key" => spec_key(spec), "position" => spec["position"] || (index + 1))
    end
  end

  def sync!
    rows = @workflow.steps.unscope(:order).includes(:sub_steps).lock.to_a.index_by(&:id)
    park_positions(rows.values)
    key_map = write_steps(rows)
    retire_others(rows, key_map)
    write_dependencies(key_map)
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
    @specs.each_with_object({}) do |spec, key_map|
      step = rows[spec["id"].presence&.to_i] || @workflow.steps.new
      attrs = spec.slice(*STEP_COLUMNS)
      Versions::Snapshots::Workflow::STEP_REFERENCES.each do |column, model|
        attrs[column] = self.class.existing_ids(model, attrs[column]) if attrs.key?(column)
      end
      attrs["agent_id"] = nil if attrs["agent_id"].present? && !Agent.exists?(attrs["agent_id"])
      step.assign_attributes(attrs.merge("depends_on_step_ids" => [], "deleted_at" => nil))
      step.save!
      write_sub_steps(step, Array(spec["sub_steps"]))
      key_map[spec["key"]] = step.id
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

  def write_dependencies(key_map)
    by_key = @specs.index_by { |s| s["key"] }
    in_dependency_order(by_key).each do |key|
      deps = Array(by_key[key]["depends_on_step_ids"]).filter_map { |dep| key_map[dep.to_s] }
      next if deps.empty?

      Step.find(key_map.fetch(key)).update!(depends_on_step_ids: deps)
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
      attrs = spec.slice(*SUB_STEP_COLUMNS)
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
