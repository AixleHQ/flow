# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Workflows
        # The builder's Save: the whole workflow — its fields, every step in
        # order and each step's sub-steps — in one request, applied in one
        # transaction and recorded as one version. `base_version` is the version
        # the editor loaded; a newer one answers 409 instead of overwriting.
        class AggregatesController < Workflows::ApplicationController
          STEP_FIELDS = [
            :id, :key, :name, :instructions, :agent_id, :allow_non_interactive, :skip_policy, :on_failure,
            :max_retries, :bmad_enabled, :required_agent_runtime, :preferred_model,
            { input_asset_specs: %i[name asset_type required],
              output_asset_specs: %i[name asset_type required name_pattern],
              tool_ids: [], mcp_server_ids: [], skill_ids: [], asset_ids: [], repository_ids: [],
              config_item_ids: [], depends_on_step_ids: [],
              sub_steps: %i[id name instructions required] }
          ].freeze

          def update
            workflow = current_workflow
            payload = aggregate_params
            WorkflowAggregateSave.new(workflow, payload).validate!
            version = Versions.save!(workflow, actor: version_actor, base_version: params.require(:base_version)) do
              WorkflowAggregateSave.new(workflow, payload).apply!
            end
            workflow.reload

            render json: {
              workflow: WorkflowResource.new(workflow).to_h,
              steps: workflow.steps.not_deleted.includes(:sub_steps).map { |s| StepResource.new(s).to_h },
              currentVersionNumber: workflow.current_version_number,
              versionCreated: version.present?
            }
          rescue WorkflowAggregateSave::Invalid => e
            render json: { errors: [ e.message ] }, status: :unprocessable_entity
          end

          private

          def aggregate_params
            params.require(:aggregate).permit(:name, :description, config: {}, steps: STEP_FIELDS).to_h
          end
        end
      end
    end
  end
end
