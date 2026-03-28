# frozen_string_literal: true

module InternalTools
  module MetaToolHelpers
    private

    def require_project_context!
      raise WorkflowContextError, "This tool requires a project context" unless project
    end

    def target_project
      if params[:project_id].present?
        Project.find(params[:project_id])
      else
        project
      end
    end

    # Store/read state via session metadata (works for both standalone and workflow sessions)
    def store_in_context(key, value)
      if workflow_run
        ctx = workflow_run.shared_context || {}
        ctx[key.to_s] = value
        workflow_run.update!(shared_context: ctx)
      elsif session
        meta = session.metadata || {}
        meta["builder_context"] ||= {}
        meta["builder_context"][key.to_s] = value
        session.update!(metadata: meta)
      end
    end

    def read_from_context(key)
      if workflow_run
        workflow_run.shared_context&.dig(key.to_s)
      elsif session
        session.metadata&.dig("builder_context", key.to_s)
      end
    end

    def target_workflow_id
      params[:workflow_id] || read_from_context("target_workflow_id")
    end

    def find_target_workflow!
      wf_id = target_workflow_id
      raise "No target workflow. Create one first with meta_create_workflow or pass workflow_id." unless wf_id

      Workflow.find(wf_id)
    end

    def broadcast_meta_activity(action:, entity_type:, entity_name:, entity_id:, details: {})
      # Broadcast is best-effort, works in both workflow and standalone contexts
      payload = {
        "type" => "meta_activity",
        "data" => {
          action: action, entity_type: entity_type, entity_name: entity_name,
          entity_id: entity_id, details: details, timestamp: Time.current.iso8601
        }
      }

      if workflow_run
        WorkflowRunChannel.broadcast_to(workflow_run, payload)
      elsif session
        TerminalSessionChannel.broadcast_to(session, payload)
      end
    rescue StandardError => e
      Rails.logger.warn("[MetaToolHelpers] Broadcast failed: #{e.message}")
    end
  end
end
