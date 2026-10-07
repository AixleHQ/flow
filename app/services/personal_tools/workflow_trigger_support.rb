# frozen_string_literal: true

module PersonalTools
  # Shared lookup for the workflow-trigger tools, mirroring
  # Api::V1::Projects::Workflows::TriggersController — one surface over two
  # record kinds:
  #   column                                      → ColumnWorkflowBinding (card enters a board column)
  #   chat / schedule / webhook / event / tracker → TriggerBinding
  # Both describe a trigger through WorkflowTriggers::Serializer.
  module WorkflowTriggerSupport
    KINDS = WorkflowTriggers::Creator::KINDS
    CHAT_PROVIDERS = Chat::PROVIDERS.keys.freeze
    STATUS_REPORTING = %w[none failures lifecycle].freeze
    TRIGGER_MODES = %w[auto manual].freeze
    SUBJECT_POLICIES = %w[none existing_task create_task find_or_create_task].freeze
    AIXLE_CHANGES = %w[ignore other_workflows always].freeze
    VERIFICATION_STRATEGIES = %w[none slack_v0 hmac_sha256 shared_token].freeze

    # Mutable fields, mirroring the controller's permit lists.
    BINDING_FIELDS = %i[name trigger_mode enabled cooldown_seconds status_reporting
                        subject_policy subject_column_id subject_title_template
                        project_tracker_id aixle_changes].freeze
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
      WorkflowTriggers::Serializer.new.column(trigger)
    end

    def serialize_binding(trigger, endpoint: nil)
      endpoints = endpoint ? { trigger.event_type => endpoint } : WorkflowTriggers::Serializer.endpoints_for([ trigger ])
      WorkflowTriggers::Serializer.new(webhook_endpoints: endpoints).binding(trigger)
    end

    def serialize_bindings(triggers)
      serializer = WorkflowTriggers::Serializer.new(webhook_endpoints: WorkflowTriggers::Serializer.endpoints_for(triggers))
      triggers.map { |trigger| serializer.binding(trigger) }
    end
  end
end
