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
      param :status_reporting, type: :string, enum: WorkflowTriggerSupport::STATUS_REPORTING,
                               description: "What a run tells the place it came from. none; failures (one message or tracker " \
                                            "comment when it fails); lifecycle (chat only: one status card in the thread, " \
                                            "edited as the run starts and ends). Chat triggers default to lifecycle."
      param :subject_policy, type: :string, enum: WorkflowTriggerSupport::SUBJECT_POLICIES,
                             description: "Which board task the run is about: none, existing_task, create_task, or " \
                                          "find_or_create_task. The last two need subject_column_id."
      param :subject_column_id, type: :integer, description: "Board column the new card lands in when subject_policy is create_task."
      param :subject_title_template, type: :string, description: "Title template for the card created by subject_policy=create_task."
      param :project_tracker_id, type: :integer,
                                 description: "kind=tracker: the project tracker to listen to; null for any tracker."
      param :aixle_changes, type: :string, enum: WorkflowTriggerSupport::AIXLE_CHANGES,
                            description: "kind=tracker: ignore, other_workflows or always — what to do with changes Aixle made."
      param :copy_attachments, type: :boolean,
                               description: "kind=tracker: copy the issue's files onto the run's task when a run starts."
      param :chat_provider, type: :string, enum: WorkflowTriggerSupport::CHAT_PROVIDERS,
                            description: "kind=chat: move the trigger to another messenger. Its channel is dropped."
      param :chat_channel_id, type: :integer,
                              description: "kind=chat: the channel to listen to, from list_chat_channels."
      param :run_as_user_id, type: :integer,
                             description: "Off-board kinds: the project member (from list_project_members) whose agent " \
                                          "and limits the trigger's runs use from now on; clears run_as_team_id. Company " \
                                          "admins and the project owner only; the member needs an agent connected."
      param :run_as_team_id, type: :integer,
                             description: "Off-board kinds: the project team (from list_project_teams) whose members " \
                                          "run the trigger from now on, one picked per run by the team's strategy. " \
                                          "Pass 0 to stop running as a team. Company admins and the project owner only."
      param :filter_predicate, type: :object,
                               description: "Replaces the whole predicate: only fire when the event data contains " \
                                            "these key/value pairs. Pass {} to clear it; a chat trigger keeps its messenger."
      param :schedule_config, type: :object,
                              description: "Replaces the whole schedule: {\"cron\": \"0 9 * * 1-5\", \"timezone\": " \
                                           "\"Europe/Berlin\"}. ALWAYS pass timezone explicitly — an empty timezone " \
                                           "makes Temporal schedule in UTC, which drifts by an hour under DST."
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)

      params[:kind].to_s == "column" ? update_column(project, workflow) : update_binding(project, workflow)
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
      if params[:run_as_user_id] || params.key?(:run_as_team_id)
        return error("A column trigger runs as the person the card is on — it has no run_as_user_id")
      end

      trigger = find_column_trigger!(project, workflow, params[:trigger_id])
      attrs = column_binding_attrs
      return error("No fields to update — a column trigger accepts trigger_mode and cooldown_seconds") if attrs.empty?

      trigger.update!(attrs)
      success(serialize_column(trigger))
    end

    def update_binding(project, workflow)
      team_given = params.key?(:run_as_team_id)
      if params[:run_as_user_id] || team_given
        authorize!(project, :change_run_as?, policy: Api::V1::Projects::Workflows::TriggersPolicy, project: project)
      end
      trigger = find_event_trigger!(workflow, params[:trigger_id])
      attrs = trigger_binding_attrs
      if attrs.empty? && params[:chat_provider].blank? && params[:run_as_user_id].blank? && !team_given
        return error("No fields to update")
      end

      trigger.assign_attributes(attrs)
      trigger.assign_chat_provider(params[:chat_provider])
      team_id = team_given ? params[:run_as_team_id].to_i.nonzero? : WorkflowTriggers::RunAs::KEEP_TEAM
      WorkflowTriggers::RunAs.save!(trigger, actor: user, user_id: params[:run_as_user_id], team_id: team_id) do
        trigger.save_checking_chat!
      end
      success(serialize_binding(trigger))
    end
  end
end
