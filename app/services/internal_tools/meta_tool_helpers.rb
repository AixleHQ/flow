# frozen_string_literal: true

module InternalTools
  module MetaToolHelpers
    private

    # A builder session acts for the user who launched it, inside that
    # session's project and nowhere else — ids in params are never trusted to
    # pick another project.
    def require_project_context!
      raise WorkflowContextError, "This tool requires a project context" unless project

      unless Web::Company::Projects::AixleBuilderPolicy.new(ProjectContext.new(acting_user, {}, project: project), nil).start?
        raise WorkflowContextError, "The session owner can no longer edit this project"
      end

      pin_to_session_project!(:project_id)
      pin_to_session_project!(:scope_id)
    end

    def acting_user
      workflow_run&.user || session.try(:user)
    end

    def target_project
      project
    end

    def pin_to_session_project!(key)
      return if params[key].blank? || params[key].to_i == project.id

      raise WorkflowContextError, "Builder tools act only on this session's project (#{project.id}); #{key} #{params[key]} is not allowed"
    end

    def project_workflows
      Workflow.visible_for_project(project)
    end

    def find_project_step!(id)
      Step.not_deleted.where(workflow_id: project_workflows.select(:id)).find(id)
    end

    def find_project_sub_step!(id)
      SubStep.where(step_id: Step.where(workflow_id: project_workflows.select(:id)).select(:id)).find(id)
    end

    def project_board_columns
      BoardColumn.where(board_id: Board.where(project_id: project.id).select(:id))
    end

    def find_project_column_binding!(id)
      ColumnWorkflowBinding.where(board_column_id: project_board_columns.select(:id)).find(id)
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

      project_workflows.find(wf_id)
    end

    def broadcast_meta_activity(action:, entity_type:, entity_name:, entity_id:, details: {})
      activity = {
        "action" => action, "entity_type" => entity_type, "entity_name" => entity_name,
        "entity_id" => entity_id, "details" => details, "timestamp" => Time.current.iso8601
      }

      persist_activity(activity)
    rescue StandardError => e
      Rails.logger.warn("[MetaToolHelpers] Broadcast/persist failed: #{e.class} — #{e.message}")
    end

    def persist_activity(activity)
      target = session || workflow_run
      return unless target.respond_to?(:metadata)

      meta = target.metadata || {}
      meta["builder_activities"] ||= []
      meta["builder_activities"] << activity
      meta["builder_activities"] = meta["builder_activities"].last(100)
      target.update_column(:metadata, meta)
      target.broadcast_refresh_to(target)
    end
  end
end
