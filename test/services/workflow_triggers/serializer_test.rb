# frozen_string_literal: true

require "test_helper"

class WorkflowTriggers::SerializerTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project, name: "Intake")
  end

  test "a webhook trigger names its workflow, its source, its URL and how it is verified" do
    endpoint = WebhookEndpoint.create_for_trigger!(project: @project, created_by: @user, verification_strategy: "hmac_sha256")
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                       event_type: endpoint.config["event_type"])

    serializer = WorkflowTriggers::Serializer.new(webhook_endpoints: WorkflowTriggers::Serializer.endpoints_for([ binding ]))
    payload = serializer.binding(binding)

    assert_equal [ "webhook", "webhook", nil ], payload.values_at(:kind, :source, :chat_provider)
    assert_equal [ "hmac_sha256", "https://#{Settings.domain}/webhooks/in/#{endpoint.slug}" ],
                 payload.values_at(:verification_strategy, :webhook_url)
    assert_equal [ @workflow.id, "Intake" ], payload.values_at(:workflow_id, :workflow_name)
    assert_not payload.key?(:webhook_secret)
  end

  test "a Slack trigger is a chat trigger whose messenger is Slack" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message")

    payload = WorkflowTriggers::Serializer.new.binding(binding)

    assert_equal [ "chat", "chat", "slack" ], payload.values_at(:kind, :source, :chat_provider)
    assert_nil payload[:webhook_url]
  end

  test "a board-column trigger is always on, and comes from the board" do
    column = create(:board_column, board: create(:board, project: @project), name: "Inbox")
    binding = ColumnWorkflowBinding.create!(board_column: column, workflow: @workflow, created_by: @user)

    payload = WorkflowTriggers::Serializer.new.column(binding)

    assert_equal [ "column", "board", "Inbox", true, "Intake" ], payload.values_at(:kind, :source, :column_name, :enabled, :workflow_name)
    assert_equal({ id: @user.id, name: @user.name }, payload[:created_by])
  end
end
