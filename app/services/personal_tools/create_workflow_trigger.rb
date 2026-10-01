# frozen_string_literal: true

module PersonalTools
  class CreateWorkflowTrigger < Base
    include WorkflowTriggerSupport

    tool do
      display_name "Create Workflow Trigger"
      description "Connect a trigger to a workflow so it launches on its own: a card entering a " \
                  "board column (kind=column), a Slack message (slack), a cron schedule (schedule), " \
                  "an inbound webhook (webhook), an event in a task tracker connected to the project " \
                  "(tracker: event_type tracker.issue.created, tracker.issue.status_changed, " \
                  "tracker.issue.assigned or tracker.comment.created; project_tracker_id picks one tracker, " \
                  "none means any), or a custom platform event (event). " \
                  "IMPORTANT: the off-board kinds (slack, schedule, webhook, event, tracker) fire unattended, " \
                  "so EVERY step of the workflow must have auto-run (allow_non_interactive) enabled — " \
                  "otherwise this call is rejected and the error names the steps still waiting on a " \
                  "human. Column triggers are exempt: their manual mode puts a person on the button. " \
                  "kind=webhook also provisions an inbound endpoint and returns webhook_url and " \
                  "webhook_secret; the secret is shown only in this response."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :kind, type: :string, enum: WorkflowTriggerSupport::KINDS, required: true,
                   description: "What launches the workflow."
      param :board_column_id, type: :integer,
                              description: "Board column whose incoming cards fire the workflow. Required for kind=column."
      param :event_type, type: :string,
                         description: "Event name for kind=event — one the platform emits: 'slack.message', or an " \
                                      "inbound webhook's own 'webhook.<token>' (list_workflow_triggers shows it). " \
                                      "Nothing emits GitHub events; start a workflow from GitHub with kind=webhook. " \
                                      "For kind=tracker, one of the tracker.* types. Ignored for the other kinds, " \
                                      "which set their own event type."
      param :name, type: :string, description: "Human-readable label for this trigger."
      param :trigger_mode, type: :string, enum: WorkflowTriggerSupport::TRIGGER_MODES,
                           description: "auto starts the run immediately; manual only offers it. Defaults to auto."
      param :enabled, type: :boolean, description: "Whether the trigger fires. Defaults to true; column triggers are always on."
      param :cooldown_seconds, type: :integer, description: "Minimum gap between two firings. Defaults to 5 for column triggers, 0 otherwise."
      param :notify_on_failure, type: :boolean,
            description: "Post to the triggering Slack thread when a run from this trigger fails, with the error (default true; Slack triggers only)."
      param :subject_policy, type: :string, enum: WorkflowTriggerSupport::SUBJECT_POLICIES,
                             description: "Which board task the run is about: none, existing_task, create_task, or " \
                                          "find_or_create_task (tracker triggers: reuse the task linked to the " \
                                          "issue, else create one). The last two need subject_column_id."
      param :subject_column_id, type: :integer, description: "Board column the new card lands in when subject_policy is create_task."
      param :subject_title_template, type: :string, description: "Title template for the card created by subject_policy=create_task."
      param :project_tracker_id, type: :integer,
                                 description: "kind=tracker: the project tracker to listen to. Omit for any tracker in the project."
      param :aixle_changes, type: :string, enum: WorkflowTriggerSupport::AIXLE_CHANGES,
                            description: "kind=tracker: what to do with changes Aixle itself made. ignore (default), " \
                                         "other_workflows (chain workflows, never re-enter one), or always."
      param :filter_predicate, type: :object,
                               description: "Only fire when the event data contains these key/value pairs, " \
                                            "e.g. {\"channel\": \"C123\"}. Empty means every event of this type."
      param :schedule_config, type: :object,
                              description: "Required for kind=schedule: {\"cron\": \"0 9 * * 1-5\", \"timezone\": " \
                                           "\"Europe/Berlin\"}. ALWAYS pass timezone explicitly — an empty timezone " \
                                           "makes Temporal schedule in UTC, which drifts by an hour under DST."
      param :verification_strategy, type: :string, enum: WorkflowTriggerSupport::VERIFICATION_STRATEGIES,
                                    description: "How the inbound webhook is authenticated (kind=webhook). Defaults to " \
                                                 "shared_token; none lets anyone who has the URL run the workflow."
      param :secret, type: :string, description: "Shared secret for the webhook's verification strategy (kind=webhook). " \
                                                 "Generated when omitted."
    end

    def execute
      kind = params[:kind].to_s
      return error("Unsupported trigger kind: #{kind}") unless WorkflowTriggerSupport::KINDS.include?(kind)

      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)

      result = WorkflowTriggers::Creator.call(
        project: project, workflow: workflow, user: user, kind: kind, attributes: creator_attributes(kind)
      )
      success(serialize_result(result))
    rescue WorkflowTriggers::Creator::BoardMissingError
      error("This project has no board — create one with setup_board before adding a column trigger.")
    rescue ActiveRecord::RecordNotFound
      error("Board column #{params[:board_column_id]} not found on this project's board")
    rescue ActiveRecord::RecordInvalid => e
      error(e.record.errors.full_messages.join(", "))
    rescue Temporalio::Error => e
      # Schedule triggers reconcile onto Temporal synchronously on save: the
      # binding IS persisted and only the scheduling failed. Re-saving retries,
      # and the worker-boot sync re-reconciles.
      Rails.logger.error("[personal-mcp] Temporal scheduling failed: #{e.message}")
      error("Trigger saved, but scheduling it failed — re-save to retry. (#{e.message})")
    end

    private

    def creator_attributes(kind)
      return params.to_h.symbolize_keys.slice(:board_column_id, :trigger_mode, :cooldown_seconds) if kind == "column"

      trigger_binding_attrs.merge(
        event_type: params[:event_type],
        verification_strategy: params[:verification_strategy],
        secret: params[:secret]
      )
    end

    def serialize_result(result)
      return serialize_column(result.trigger) if result.kind == "column"

      payload = serialize_binding(result.trigger)
      return payload unless result.webhook_endpoint

      payload.merge(
        webhook_url: webhook_url(result.webhook_endpoint.slug),
        webhook_secret: result.webhook_endpoint.secret,
        verification_strategy: result.webhook_endpoint.verification_strategy
      )
    end

    def webhook_url(slug)
      "https://#{Settings.domain}/webhooks/in/#{slug}"
    end
  end
end
