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
          WorkflowStepSync.new(record, Array(snapshot["steps"])).sync!
          record.steps.reset
        end

        private

        def existing_config(config)
          CONFIG_REFERENCES.each_with_object(config.dup) do |(key, model), memo|
            memo[key] = WorkflowStepSync.existing_ids(model, config[key]) if config.key?(key)
          end
        end
      end
    end
  end
end
