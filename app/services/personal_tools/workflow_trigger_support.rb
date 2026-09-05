# frozen_string_literal: true

module PersonalTools
  # Shared lookup and serialization for the workflow-trigger tools, mirroring
  # Api::V1::Projects::Workflows::TriggersController — one surface over two
  # record kinds:
  #   column                             → ColumnWorkflowBinding (card enters a board column)
  #   slack / schedule / webhook / event → TriggerBinding
  # The UI and the personal MCP must describe the same trigger the same way, so
  # the field sets below stay in step with the controller's serializers.
  module WorkflowTriggerSupport
    KINDS = %w[column slack schedule webhook event].freeze
    TRIGGER_MODES = %w[auto manual].freeze
    SUBJECT_POLICIES = %w[none existing_task create_task].freeze
    VERIFICATION_STRATEGIES = %w[none slack_v0 hmac_sha256 shared_token].freeze

    # Mutable fields, mirroring the controller's permit lists.
    BINDING_FIELDS = %i[name trigger_mode enabled cooldown_seconds notify_on_failure
                        subject_policy subject_column_id subject_title_template].freeze
    COLUMN_FIELDS = %i[trigger_mode cooldown_seconds].freeze
    SCHEDULE_KEYS = %w[cron timezone].freeze

    private

    # Column bindings reached only through this project's board — never a
    # global ColumnWorkflowBinding lookup by id.
    def column_bindings(project, workflow)
      ColumnWorkflowBinding
        .joins(board_column: :board)
        .where(boards: { project_id: project.id }, workflow_id: workflow.id)
    end

    def find_column_trigger!(project, workflow, id)
      trigger = column_bindings(project, workflow).find_by(id: id)
      raise Base::NotFoundError, "Column trigger #{id} not found on workflow #{workflow.id}" unless trigger

      trigger
    end

    def find_event_trigger!(workflow, id)
      trigger = workflow.trigger_bindings.find_by(id: id)
      raise Base::NotFoundError, "Trigger #{id} not found on workflow #{workflow.id}" unless trigger

      trigger
    end

    # Only the keys the caller actually sent: an update must not blank a field
    # that was simply omitted.
    def trigger_binding_attrs
      attrs = BINDING_FIELDS.each_with_object({}) { |key, acc| acc[key] = params[key] if params.key?(key) }
      attrs[:filter_predicate] = object_param(:filter_predicate) if params.key?(:filter_predicate)
      attrs[:schedule_config] = object_param(:schedule_config).slice(*SCHEDULE_KEYS) if params.key?(:schedule_config)
      attrs
    end

    def column_binding_attrs
      COLUMN_FIELDS.each_with_object({}) { |key, acc| acc[key] = params[key] if params.key?(key) }
    end

    def object_param(key)
      value = params[key]
      value.is_a?(Hash) ? value.to_h : {}
    end

    def serialize_column(trigger)
      {
        id: trigger.id,
        kind: "column",
        event_type: "board.column_changed",
        board_column_id: trigger.board_column_id,
        column_name: trigger.board_column.name,
        trigger_mode: trigger.trigger_mode,
        cooldown_seconds: trigger.cooldown_seconds,
        enabled: true
      }
    end

    def serialize_binding(trigger)
      {
        id: trigger.id,
        kind: binding_kind(trigger.event_type),
        event_type: trigger.event_type,
        name: trigger.name,
        filter_predicate: trigger.filter_predicate,
        trigger_mode: trigger.trigger_mode,
        subject_policy: trigger.subject_policy,
        subject_column_id: trigger.subject_column_id,
        subject_title_template: trigger.subject_title_template,
        schedule_config: trigger.schedule_config,
        cooldown_seconds: trigger.cooldown_seconds,
        notify_on_failure: trigger.notify_on_failure,
        enabled: trigger.enabled
      }
    end

    def binding_kind(event_type)
      case event_type
      when "slack.message" then "slack"
      when "schedule.fired" then "schedule"
      when /\Awebhook\./ then "webhook"
      else "event"
      end
    end
  end
end
