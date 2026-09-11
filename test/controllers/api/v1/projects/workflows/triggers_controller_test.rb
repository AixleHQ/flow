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

          test "a slack trigger reports failures back to Slack unless it is switched off" do
            post :create, params: {
              project_id: @project.id, workflow_id: @workflow.id,
              trigger: { kind: "slack", filter_predicate: { channel: "C1" }, subject_policy: "none" }
            }

            assert_response :created
            assert json["notify_on_failure"], "a new slack trigger notifies on failure by default"
            binding = TriggerBinding.find(json["id"])
            assert binding.notify_on_failure

            patch :update, params: {
              project_id: @project.id, workflow_id: @workflow.id, id: binding.id,
              trigger: { notify_on_failure: false }
            }

            assert_response :success
            assert_not json["notify_on_failure"]
            assert_not binding.reload.notify_on_failure
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

          test "create column trigger returns 422 when the project has no board" do
            boardless_project = create(:project, company: @company, owner: @user)
            boardless_workflow = create(:workflow, scope: boardless_project)

            assert_no_difference -> { ColumnWorkflowBinding.count } do
              post :create, params: {
                project_id: boardless_project.id, workflow_id: boardless_workflow.id,
                trigger: { kind: "column", board_column_id: 0, trigger_mode: "auto", cooldown_seconds: 5 }
              }
            end

            assert_response :unprocessable_entity
            assert_match(/no board/i, json["errors"].first)
          end

          test "create schedule trigger persists schedule_config" do
            assert_difference -> { TriggerBinding.count }, 1 do
              post :create, params: {
                project_id: @project.id, workflow_id: @workflow.id,
                trigger: { kind: "schedule", schedule_config: { cron: "0 9 * * 1-5", timezone: "UTC" }, subject_policy: "none" }
              }
            end
            assert_response :created
            assert_equal "schedule", json["kind"]
            assert_equal "schedule.fired", json["event_type"]
            assert_equal "0 9 * * 1-5", json["schedule_config"]["cron"]
          end

          test "unsupported kind is rejected" do
            post :create, params: { project_id: @project.id, workflow_id: @workflow.id, trigger: { kind: "nonsense" } }
            assert_response :unprocessable_entity
          end

          test "creating a trigger records the signed-in user as its creator" do
            post :create, params: {
              project_id: @project.id, workflow_id: @workflow.id,
              trigger: { kind: "column", board_column_id: @column.id, trigger_mode: "auto", cooldown_seconds: 5 }
            }
            assert_response :created
            assert_equal({ "id" => @user.id, "name" => @user.name }, json["created_by"])
            assert_equal @user.id, ColumnWorkflowBinding.find(json["id"]).created_by_id

            post :create, params: {
              project_id: @project.id, workflow_id: @workflow.id,
              trigger: { kind: "slack", filter_predicate: { channel: "C1" }, subject_policy: "none" }
            }
            assert_response :created
            assert_equal({ "id" => @user.id, "name" => @user.name }, json["created_by"])
            assert_equal @user.id, TriggerBinding.find(json["id"]).created_by_id
          end

          test "index names the creator of each trigger, and reports none for a trigger without one" do
            ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow, created_by: @user,
                                          trigger_mode: :auto, cooldown_seconds: 0)
            orphan = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                              event_type: "slack.message")
            orphan.update_column(:created_by_id, nil)

            get :index, params: { project_id: @project.id, workflow_id: @workflow.id }

            assert_response :success
            by_kind = json["triggers"].index_by { |t| t["kind"] }
            assert_equal({ "id" => @user.id, "name" => @user.name }, by_kind["column"]["created_by"])
            assert_nil by_kind["slack"]["created_by"]
          end

          test "editing a trigger leaves its creator alone" do
            creator = create(:user, :onboarding_completed, company: @company)
            binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: creator,
                                               event_type: "slack.message", name: "before")
            column_binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow,
                                                           created_by: creator, trigger_mode: :auto, cooldown_seconds: 0)

            patch :update, params: {
              project_id: @project.id, workflow_id: @workflow.id, id: binding.id,
              trigger: { name: "after", enabled: false }
            }
            assert_response :success
            assert_equal creator.id, binding.reload.created_by_id
            assert_equal({ "id" => creator.id, "name" => creator.name }, json["created_by"])

            patch :update, params: {
              project_id: @project.id, workflow_id: @workflow.id, id: column_binding.id, kind: "column",
              trigger: { trigger_mode: "manual", cooldown_seconds: 30 }
            }
            assert_response :success
            assert_equal creator.id, column_binding.reload.created_by_id
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
