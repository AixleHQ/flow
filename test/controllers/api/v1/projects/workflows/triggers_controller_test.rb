# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      module Workflows
        class TriggersControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @user)
            @board = create(:board, project: @project)
            @column = create(:board_column, board: @board)
            @workflow = create(:workflow, scope: @project)
            sign_in @user
          end

          def json
            JSON.parse(response.body)
          end

          test "index lists column and event triggers for the workflow" do
            ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow, trigger_mode: :auto, cooldown_seconds: 0)
            create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")

            get :index, params: { project_id: @project.id, workflow_id: @workflow.id }

            assert_response :success
            kinds = json["triggers"].map { |t| t["kind"] }.sort
            assert_equal %w[column slack], kinds
          end

          test "create slack trigger persists a TriggerBinding" do
            assert_difference -> { TriggerBinding.count }, 1 do
              post :create, params: {
                project_id: @project.id, workflow_id: @workflow.id,
                trigger: { kind: "slack", filter_predicate: { channel: "C1" }, subject_policy: "create_task", subject_column_id: @column.id }
              }
            end
            assert_response :created
            assert_equal "slack.message", json["event_type"]
            assert_equal "slack", json["kind"]
          end

          test "create webhook trigger provisions an endpoint and returns its url + secret" do
            assert_difference -> { TriggerBinding.count } => 1, -> { WebhookEndpoint.count } => 1 do
              post :create, params: {
                project_id: @project.id, workflow_id: @workflow.id,
                trigger: { kind: "webhook", verification_strategy: "hmac_sha256", secret: "shh",
                           filter_predicate: { ref: "refs/heads/main" }, subject_policy: "none" }
              }
            end
            assert_response :created
            assert_match %r{/webhooks/in/wh-}, json["webhook_url"]
            assert_equal "shh", json["webhook_secret"]
            assert_match(/\Awebhook\./, json["event_type"])
          end

          test "create column trigger persists a ColumnWorkflowBinding" do
            assert_difference -> { ColumnWorkflowBinding.count }, 1 do
              post :create, params: {
                project_id: @project.id, workflow_id: @workflow.id,
                trigger: { kind: "column", board_column_id: @column.id, trigger_mode: "auto", cooldown_seconds: 7 }
              }
            end
            assert_response :created
            assert_equal "column", json["kind"]
            assert_equal 7, json["cooldown_seconds"]
          end

          test "unsupported kind is rejected" do
            post :create, params: { project_id: @project.id, workflow_id: @workflow.id, trigger: { kind: "nonsense" } }
            assert_response :unprocessable_entity
          end

          test "destroy removes an event trigger" do
            binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")
            assert_difference -> { TriggerBinding.count }, -1 do
              delete :destroy, params: { project_id: @project.id, workflow_id: @workflow.id, id: binding.id }
            end
            assert_response :no_content
          end

          test "destroy removes a column trigger" do
            binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow, trigger_mode: :auto, cooldown_seconds: 0)
            assert_difference -> { ColumnWorkflowBinding.count }, -1 do
              delete :destroy, params: { project_id: @project.id, workflow_id: @workflow.id, id: binding.id, kind: "column" }
            end
            assert_response :no_content
          end
        end
      end
    end
  end
end
