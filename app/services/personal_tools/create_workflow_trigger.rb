# frozen_string_literal: true

module PersonalTools
  class CreateWorkflowTrigger < Base
    include WorkflowTriggerSupport

    # A column trigger binds to a board column, which cannot exist without a
    # board — reported as a tool error, not a lookup failure.
    BoardMissingError = Class.new(StandardError)

    tool do
      display_name "Create Workflow Trigger"
      description "Connect a trigger to a workflow so it launches on its own: a card entering a " \
                  "board column (kind=column), a Slack message (slack), a cron schedule (schedule), " \
                  "an inbound webhook (webhook), or a custom platform event (event). " \
                  "IMPORTANT: the off-board kinds (slack, schedule, webhook, event) fire unattended, " \
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
                         description: "Platform event name for kind=event (e.g. 'github.push'). Ignored for the " \
                                      "other kinds, which set their own event type."
      param :name, type: :string, description: "Human-readable label for this trigger."
      param :trigger_mode, type: :string, enum: WorkflowTriggerSupport::TRIGGER_MODES,
                           description: "auto starts the run immediately; manual only offers it. Defaults to auto."
      param :enabled, type: :boolean, description: "Whether the trigger fires. Defaults to true; column triggers are always on."
      param :cooldown_seconds, type: :integer, description: "Minimum gap between two firings. Defaults to 5 for column triggers, 0 otherwise."
      param :subject_policy, type: :string, enum: WorkflowTriggerSupport::SUBJECT_POLICIES,
                             description: "Which board task the run is about: none, existing_task, or create_task " \
                                          "(create_task also needs subject_column_id)."
      param :subject_column_id, type: :integer, description: "Board column the new card lands in when subject_policy is create_task."
      param :subject_title_template, type: :string, description: "Title template for the card created by subject_policy=create_task."
      param :filter_predicate, type: :object,
                               description: "Only fire when the event data contains these key/value pairs, " \
                                            "e.g. {\"channel\": \"C123\"}. Empty means every event of this type."
      param :schedule_config, type: :object,
                              description: "Required for kind=schedule: {\"cron\": \"0 9 * * 1-5\", \"timezone\": " \
                                           "\"Europe/Berlin\"}. ALWAYS pass timezone explicitly — an empty timezone " \
                                           "makes Temporal schedule in UTC, which drifts by an hour under DST."
      param :verification_strategy, type: :string, enum: WorkflowTriggerSupport::VERIFICATION_STRATEGIES,
                                    description: "How the inbound webhook is authenticated (kind=webhook). Defaults to none."
      param :secret, type: :string, description: "Shared secret for the webhook's verification strategy (kind=webhook)."
    end

    def execute
      kind = params[:kind].to_s
      return error("Unsupported trigger kind: #{kind}") unless WorkflowTriggerSupport::KINDS.include?(kind)

      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)

      success(build_trigger(project, workflow, kind))
    rescue BoardMissingError
      error("This project has no board. Create a board before adding a column trigger.")
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

    def build_trigger(project, workflow, kind)
      case kind
      when "column" then create_column_trigger(project, workflow)
      when "webhook" then create_webhook_trigger(project, workflow)
      else create_event_trigger(project, workflow, kind)
      end
    end

    def create_column_trigger(project, workflow)
      board = project.board
      raise BoardMissingError unless board

      column = board.board_columns.find_by(id: params[:board_column_id])
      raise NotFoundError, "Board column #{params[:board_column_id]} not found on this project's board" unless column

      serialize_column(ColumnWorkflowBinding.create!(
                         board_column: column,
                         workflow: workflow,
                         trigger_mode: params[:trigger_mode].presence || "auto",
                         cooldown_seconds: params[:cooldown_seconds].presence || 5
                       ))
    end

    def create_event_trigger(project, workflow, kind)
      event_type =
        case kind
        when "slack" then "slack.message"
        when "schedule" then "schedule.fired"
        else params[:event_type].to_s.presence || "webhook.received"
        end

      serialize_binding(create_binding!(project, workflow, event_type))
    end

    def create_webhook_trigger(project, workflow)
      token = SecureRandom.hex(6)
      event_type = "webhook.#{token}"

      # One transaction so a rejected binding (the auto-run rule rejects most
      # first attempts) doesn't leave an orphan endpoint behind on every retry.
      endpoint, trigger = ActiveRecord::Base.transaction do
        created = WebhookEndpoint.create!(
          slug: "wh-#{token}",
          provider: :generic,
          verification_strategy: params[:verification_strategy].presence || "none",
          secret: params[:secret].presence,
          config: { "event_type" => event_type },
          project: project,
          company: project.company,
          created_by: user
        )
        [ created, create_binding!(project, workflow, event_type) ]
      end

      serialize_binding(trigger).merge(
        webhook_url: webhook_url(endpoint.slug),
        webhook_secret: endpoint.secret,
        verification_strategy: endpoint.verification_strategy
      )
    end

    def create_binding!(project, workflow, event_type)
      workflow.trigger_bindings.create!(
        trigger_binding_attrs.merge(project: project, created_by: user, event_type: event_type)
      )
    end

    def webhook_url(slug)
      "https://#{Settings.domain}/webhooks/in/#{slug}"
    end
  end
end
