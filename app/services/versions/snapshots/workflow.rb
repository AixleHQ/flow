# frozen_string_literal: true

module Versions
  module Snapshots
    # A workflow with its live steps and their live sub-steps, each keyed by id.
    # Steps and sub-steps are only ever soft-deleted, so every id a snapshot
    # names still has a row: a revert clears `deleted_at` on the ones the
    # snapshot holds and sets it on the live ones it does not, and
    # `depends_on_step_ids` needs no remapping.
    class Workflow < Base
      FIELDS = %w[name description config].freeze
      EXCLUDED = %w[id scope_type scope_id project_id company_id published_at published_by_id deleted_at
                    current_version_number created_at updated_at].freeze
      STEP_FIELDS = %w[id name instructions position agent_id preferred_model required_agent_runtime skip_policy
                       on_failure max_retries bmad_enabled allow_non_interactive input_asset_specs
                       output_asset_specs tool_ids skill_ids mcp_server_ids asset_ids repository_ids
                       config_item_ids depends_on_step_ids].freeze
      STEP_EXCLUDED = %w[workflow_id deleted_at created_at updated_at].freeze
      SUB_STEP_FIELDS = %w[id name instructions position required].freeze
      SUB_STEP_EXCLUDED = %w[step_id deleted_at created_at updated_at].freeze

      # Step id lists and the resource model each one names. Ids of rows that no
      # longer exist at all are dropped on restore; archived ones are kept (the
      # revert dialog lists them, runtime skips them).
      STEP_REFERENCES = {
        "tool_ids" => "Tool", "skill_ids" => "Skill", "mcp_server_ids" => "MCPServer",
        "asset_ids" => "Asset", "repository_ids" => "Repository", "config_item_ids" => "ConfigItem"
      }.freeze
      CONFIG_REFERENCES = {
        "base_tool_ids" => "Tool", "base_skill_ids" => "Skill", "base_mcp_server_ids" => "MCPServer",
        "base_asset_ids" => "Asset", "base_repository_ids" => "Repository", "base_config_item_ids" => "ConfigItem"
      }.freeze

      class << self
        def dump(record)
          steps = record.steps.not_deleted.reorder(:position).includes(:sub_steps).map do |step|
            sub_steps = step.sub_steps.reject(&:deleted?).sort_by { |s| [ s.position, s.id ] }
            step.attributes.slice(*STEP_FIELDS).merge(
              "sub_steps" => sub_steps.map { |sub| sub.attributes.slice(*SUB_STEP_FIELDS) }
            )
          end
          super.merge("steps" => steps)
        end

        def restore!(record, snapshot)
          record.assign_attributes(
            "name" => snapshot["name"], "description" => snapshot["description"],
            "config" => existing_config(snapshot["config"] || {})
          )
          record.save!
          StepRestorer.new(record, Array(snapshot["steps"]), self).restore!
          record.steps.reset
        end

        def existing_ids(model_name, ids)
          ids = Array(ids).compact_blank.map(&:to_i)
          return [] if ids.empty?

          found = model_name.constantize.where(id: ids).pluck(:id).to_set
          ids.select { |id| found.include?(id) }
        end

        private

        def existing_config(config)
          CONFIG_REFERENCES.each_with_object(config.dup) do |(key, model), memo|
            memo[key] = existing_ids(model, config[key]) if config.key?(key)
          end
        end
      end

      # Puts a workflow's steps and sub-steps back to a snapshot, in an order
      # that no intermediate state violates: positions are parked out of the
      # way of the unique (workflow_id, position) index, dependencies are
      # cleared before any step is validated, then set again in dependency
      # order so a transient cycle can never be observed.
      class StepRestorer
        def initialize(workflow, snapshot_steps, serializer)
          @workflow = workflow
          @snapshot_steps = snapshot_steps
          @serializer = serializer
        end

        def restore!
          rows = @workflow.steps.unscope(:order).lock.to_a.index_by(&:id)
          park_positions(rows.values)
          id_map = restore_rows(rows)
          retire_extras(rows, id_map)
          restore_dependencies(id_map)
        end

        private

        def park_positions(rows)
          highest = [ rows.filter_map(&:position).max.to_i, @snapshot_steps.map { |s| s["position"].to_i }.max.to_i ].max
          offset = highest + rows.size + @snapshot_steps.size + 1
          rows.each_with_index { |row, index| row.update_column(:position, offset + index) }
        end

        # Every snapshot step, restored without its dependencies. A step the
        # snapshot names but the database lost (hard-deleted before steps were
        # always soft-deleted) is created anew, and its old id mapped to the new.
        def restore_rows(rows)
          @snapshot_steps.each_with_object({}) do |spec, id_map|
            step = rows[spec["id"]] || @workflow.steps.new
            attrs = spec.slice(*(Workflow::STEP_FIELDS - %w[id depends_on_step_ids]))
            Workflow::STEP_REFERENCES.each { |key, model| attrs[key] = @serializer.existing_ids(model, attrs[key]) }
            attrs["agent_id"] = nil if attrs["agent_id"] && !Agent.exists?(attrs["agent_id"])
            step.assign_attributes(attrs.merge("depends_on_step_ids" => [], "deleted_at" => nil))
            step.save!
            restore_sub_steps(step, Array(spec["sub_steps"]))
            id_map[spec["id"]] = step.id
          end
        end

        def retire_extras(rows, id_map)
          kept = id_map.values.to_set
          next_free = @snapshot_steps.map { |s| s["position"].to_i }.max.to_i
          rows.each_value do |row|
            next if kept.include?(row.id)

            next_free += 1
            row.update_columns(position: next_free, depends_on_step_ids: [],
                               deleted_at: row.deleted_at || Time.current)
          end
        end

        def restore_dependencies(id_map)
          by_old_id = @snapshot_steps.index_by { |s| s["id"] }
          topological(by_old_id).each do |old_id|
            deps = Array(by_old_id[old_id]["depends_on_step_ids"]).filter_map { |dep| id_map[dep] }
            next if deps.empty?

            Step.find(id_map.fetch(old_id)).update!(depends_on_step_ids: deps)
          end
        end

        def topological(by_old_id)
          order = []
          visiting = Set.new
          visit = lambda do |id|
            return if order.include?(id) || visiting.include?(id) || !by_old_id.key?(id)

            visiting << id
            Array(by_old_id[id]["depends_on_step_ids"]).each { |dep| visit.call(dep) }
            visiting.delete(id)
            order << id
          end
          by_old_id.each_key { |id| visit.call(id) }
          order
        end

        def restore_sub_steps(step, specs)
          rows = step.sub_steps.to_a.index_by(&:id)
          kept = specs.map do |spec|
            sub = rows[spec["id"]] || step.sub_steps.new
            sub.assign_attributes(spec.slice(*(Workflow::SUB_STEP_FIELDS - %w[id])).merge("deleted_at" => nil))
            sub.save!
            sub.id
          end
          rows.each_value do |row|
            row.update_column(:deleted_at, Time.current) if !kept.include?(row.id) && row.deleted_at.nil?
          end
        end
      end
    end
  end
end
