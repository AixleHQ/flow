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

          def connect_slack!
            create(:integration, provider: :slack, status: :active, company: @company, project: nil)
          end

          test "index lists column and event triggers for the workflow" do
            ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow, trigger_mode: :auto, cooldown_seconds: 0)
            create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")

            get :index, params: { project_id: @project.id, workflow_id: @workflow.id }

            assert_response :success
            kinds = json["triggers"].map { |t| t["kind"] }.sort
            assert_equal %w[column slack], kinds
          end

          test "create tracker trigger stores its tracker and how it treats Aixle's own changes" do
            integration = create(:integration, :azure_devops, :active, company: @company, project: @project)
            tracker = create(:project_tracker, integration: integration)

            post :create, params: { project_id: @project.id, workflow_id: @workflow.id, trigger: {
              kind: "tracker", event_type: "tracker.issue.status_changed", project_tracker_id: tracker.id,
              aixle_changes: "other_workflows", subject_policy: "find_or_create_task", subject_column_id: @column.id,
              filter_predicate: { "change.to.name" => { op: "in", value: [ "Ready for AI" ] } }
            } }, as: :json

            assert_response :created
            assert_equal [ "tracker", tracker.id, "other_workflows" ],
                         [ json["kind"], json["project_tracker_id"], json["aixle_changes"] ]
            assert_equal({ "op" => "in", "value" => [ "Ready for AI" ] },
                         TriggerBinding.sole.filter_predicate["change.to.name"])
          end

          test "create slack trigger persists a TriggerBinding" do
            connect_slack!
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
            connect_slack!
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

          test "a slack trigger is refused, on create and when switched on, until the company connects Slack" do
            assert_no_difference -> { TriggerBinding.count } do
              post :create, params: {
                project_id: @project.id, workflow_id: @workflow.id,
                trigger: { kind: "slack", filter_predicate: { channel: "C1" }, subject_policy: "none" }
              }
            end
            assert_response :unprocessable_entity
            assert_equal [ TriggerBinding::SLACK_NOT_CONNECTED ], json["errors"]

            binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                               event_type: "slack.message", enabled: false)
            patch :update, params: {
              project_id: @project.id, workflow_id: @workflow.id, id: binding.id, trigger: { enabled: true }
            }
            assert_response :unprocessable_entity
            assert_not binding.reload.enabled
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

            get :index, params: { project_id: @project.id, workflow_id: @workflow.id }
            listed = json["triggers"].sole
            assert_equal [ "hmac_sha256", @workflow.id ], listed.values_at("verification_strategy", "workflow_id")
            assert_match %r{/webhooks/in/wh-}, listed["webhook_url"]
            assert_not listed.key?("webhook_secret")
          end

          test "a webhook trigger created without a strategy demands a generated shared token" do
            post :create, params: {
              project_id: @project.id, workflow_id: @workflow.id,
              trigger: { kind: "webhook", subject_policy: "none" }
            }

            assert_response :created
            endpoint = WebhookEndpoint.find_by!(slug: json["webhook_url"].split("/").last)
            assert_equal "shared_token", endpoint.verification_strategy
            assert_equal endpoint.secret, json["webhook_secret"]
            assert_operator json["webhook_secret"].length, :>=, 32
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
            connect_slack!
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

          test "destroying a webhook trigger turns its endpoint off" do
            post :create, params: { project_id: @project.id, workflow_id: @workflow.id, trigger: { kind: "webhook", subject_policy: "none" } }
            binding = TriggerBinding.find(json["id"])
            endpoint = WebhookEndpoint.find_by!(slug: json["webhook_url"].split("/").last)

            delete :destroy, params: { project_id: @project.id, workflow_id: @workflow.id, id: binding.id }

            assert_response :no_content
            assert_not endpoint.reload.enabled
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
