# frozen_string_literal: true

module WorkflowTriggers
  # Creates a workflow trigger of any kind. One home for what the triggers API,
  # the personal MCP and the template installer all do:
  #   column                             → ColumnWorkflowBinding
  #   slack / schedule / webhook / event → TriggerBinding (+ WebhookEndpoint for webhook)
  #
  # Callers serialize the result themselves; the web and MCP surfaces format it
  # differently. ActiveRecord::RecordInvalid and Temporalio::Error (a schedule
  # reconciles onto Temporal after commit) propagate to the caller.
  class Creator
    KINDS = %w[column slack schedule webhook event].freeze

    BoardMissingError = Class.new(StandardError)
    UnsupportedKindError = Class.new(StandardError)

    Result = Struct.new(:kind, :trigger, :webhook_endpoint, keyword_init: true)

    BINDING_KEYS = %i[name trigger_mode enabled cooldown_seconds notify_on_failure subject_policy
                      subject_column_id subject_title_template filter_predicate schedule_config].freeze

    def self.call(...) = new(...).call

    # @param attributes [Hash] the trigger's fields; column triggers read
    #   board_column_id / trigger_mode / cooldown_seconds, webhooks also read
    #   verification_strategy / secret, kind=event reads event_type.
    def initialize(project:, workflow:, user:, kind:, attributes: {})
      @project = project
      @workflow = workflow
      @user = user
      @kind = kind.to_s
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      case @kind
      when "column" then create_column_trigger
      when "webhook" then create_webhook_trigger
      when "slack", "schedule", "event" then Result.new(kind: @kind, trigger: create_binding!(event_type))
      else raise UnsupportedKindError, "Unsupported trigger kind: #{@kind}"
      end
    end

    private

    def create_column_trigger
      board = @project.board
      raise BoardMissingError unless board

      column = board.board_columns.find(@attributes[:board_column_id])
      trigger = ColumnWorkflowBinding.create!(
        board_column: column,
        workflow: @workflow,
        created_by: @user,
        trigger_mode: @attributes[:trigger_mode].presence || "auto",
        cooldown_seconds: @attributes[:cooldown_seconds].presence || 5
      )
      Result.new(kind: "column", trigger: trigger)
    end

    # One transaction so a rejected binding (the auto-run rule rejects most first
    # attempts) doesn't leave an orphan endpoint behind on every retry.
    def create_webhook_trigger
      ActiveRecord::Base.transaction do
        endpoint = WebhookEndpoint.create_for_trigger!(
          project: @project, created_by: @user,
          verification_strategy: @attributes[:verification_strategy], secret: @attributes[:secret]
        )
        Result.new(kind: "webhook", trigger: create_binding!(endpoint.config["event_type"]), webhook_endpoint: endpoint)
      end
    end

    def create_binding!(binding_event_type)
      @workflow.trigger_bindings.create!(
        binding_attributes.merge(project: @project, created_by: @user, event_type: binding_event_type)
      )
    end

    def event_type
      case @kind
      when "slack" then "slack.message"
      when "schedule" then "schedule.fired"
      else @attributes[:event_type].to_s.presence || "webhook.received"
      end
    end

    def binding_attributes
      @attributes.slice(*BINDING_KEYS)
    end
  end
end
