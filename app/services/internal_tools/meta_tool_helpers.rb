# frozen_string_literal: true

module InternalTools
  module MetaToolHelpers
    private

    def target_project
      if params[:project_id].present?
        Project.find(params[:project_id])
      else
        project
      end
    end

    def store_in_shared_context(key, value)
      ctx = workflow_run.shared_context || {}
      ctx[key.to_s] = value
      workflow_run.update!(shared_context: ctx)
    end

    def read_from_shared_context(key)
      workflow_run.shared_context&.dig(key.to_s)
    end

    def target_workflow_id
      params[:workflow_id] || read_from_shared_context("target_workflow_id")
    end

    def find_target_workflow!
      wf_id = target_workflow_id
      raise "No target workflow. Create one first with meta_create_workflow or pass workflow_id." unless wf_id

      Workflow.find(wf_id)
    end

    def broadcast_meta_activity(action:, entity_type:, entity_name:, entity_id:, details: {})
      WorkflowRunChannel.broadcast_to(workflow_run, {
        "type" => "meta_activity",
        "data" => {
          action: action,
          entity_type: entity_type,
          entity_name: entity_name,
          entity_id: entity_id,
          details: details,
          timestamp: Time.current.iso8601
        }
      })
    rescue StandardError => e
      Rails.logger.warn("[MetaToolHelpers] Broadcast failed: #{e.message}")
    end
  end
end
