# frozen_string_literal: true

module PersonalTools
  class UpdateWorkflowTrigger < Base
    include WorkflowTriggerSupport

    tool do
      display_name "Update Workflow Trigger"
      description "Edit an existing workflow trigger. Pass its kind together with trigger_id — " \
                  "column triggers and event triggers are separate records whose ids can collide. " \
                  "Only the fields you pass are changed. Column triggers accept trigger_mode and " \
                  "cooldown_seconds only; everything else applies to the off-board kinds. Enabling " \
                  "an off-board trigger requires auto-run (allow_non_interactive) on every step."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :trigger_id, type: :integer, description: "Trigger id (from list_workflow_triggers).", required: true
      param :kind, type: :string, enum: WorkflowTriggerSupport::KINDS, required: true,
                   description: "The trigger's kind, as reported by list_workflow_triggers."
      param :name, type: :string, description: "Human-readable label for this trigger."
      param :trigger_mode, type: :string, enum: WorkflowTriggerSupport::TRIGGER_MODES,
                           description: "auto starts the run immediately; manual only offers it."
      param :enabled, type: :boolean, description: "Whether the trigger fires."
      param :cooldown_seconds, type: :integer, description: "Minimum gap between two firings."
      param :subject_policy, type: :string, enum: WorkflowTriggerSupport::SUBJECT_POLICIES,
                             description: "Which board task the run is about: none, existing_task, or create_task " \
                                          "(create_task also needs subject_column_id)."
      param :subject_column_id, type: :integer, description: "Board column the new card lands in when subject_policy is create_task."
      param :subject_title_template, type: :string, description: "Title template for the card created by subject_policy=create_task."
      param :filter_predicate, type: :object,
                               description: "Replaces the whole predicate: only fire when the event data contains " \
                                            "these key/value pairs. Pass {} to clear it."
      param :schedule_config, type: :object,
                              description: "Replaces the whole schedule: {\"cron\": \"0 9 * * 1-5\", \"timezone\": " \
                                           "\"Europe/Berlin\"}. ALWAYS pass timezone explicitly — an empty timezone " \
                                           "makes Temporal schedule in UTC, which drifts by an hour under DST."
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)

      params[:kind].to_s == "column" ? update_column(project, workflow) : update_binding(workflow)
    rescue ActiveRecord::RecordInvalid => e
      error(e.record.errors.full_messages.join(", "))
    rescue Temporalio::Error => e
      # Schedule triggers reconcile onto Temporal synchronously on save: the
      # binding IS updated and only the scheduling failed. Re-saving retries,
      # and the worker-boot sync re-reconciles.
      Rails.logger.error("[personal-mcp] Temporal scheduling failed: #{e.message}")
      error("Trigger saved, but scheduling it failed — re-save to retry. (#{e.message})")
    end

    private

    def update_column(project, workflow)
      trigger = find_column_trigger!(project, workflow, params[:trigger_id])
      attrs = column_binding_attrs
      return error("No fields to update — a column trigger accepts trigger_mode and cooldown_seconds") if attrs.empty?

      trigger.update!(attrs)
      success(serialize_column(trigger))
    end

    def update_binding(workflow)
      trigger = find_event_trigger!(workflow, params[:trigger_id])
      attrs = trigger_binding_attrs
      return error("No fields to update") if attrs.empty?

      trigger.update!(attrs)
      success(serialize_binding(trigger))
    end
  end
end
