# frozen_string_literal: true

require "test_helper"

# Starting a workflow yourself from Slack: the Run workflow shortcut, its modal,
# and the slash command (docs/design/teams-integration.md §21).
class Webhooks::SlackRunActionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SECRET = "app-signing-secret"

  setup do
    Settings.stubs(:slack).returns(Hashie::Mash.new(client_id: "123.456", client_secret: "s3cret", signing_secret: SECRET,
                                                    scopes: "chat:write,commands"))
    stub_slack_client!
    @user = create(:user, :with_company, name: "Ada Lovelace")
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company, name: "Sales Ops")
    @workflow = create(:workflow, scope: @project, name: "Weekly Digest")
    create(:step, workflow: @workflow, name: "Render", position: 1, allow_non_interactive: true)
    @integration = Integration.create!(provider: :slack, company: @company, connected_by: @user, name: "Acme",
                                       status: :active, settings: { "team_id" => "T1" })
    @integration.update!(credentials_data: { "bot_token" => "xoxb-1" })
    create(:webhook_endpoint, slug: "slack-team-T1", provider: :slack, verification_strategy: :slack_v0, project: nil,
                              company: @company, config: { "integration_id" => @integration.id, "team_id" => "T1" })
  end

  def link!
    ChatIdentity.create!(provider: "slack", workspace_id: "T1", external_user_id: "U1", user: @user,
                         proof: "slack_sign_in", linked_at: Time.current)
  end

  def signed_post(path, form)
    raw = URI.encode_www_form(form)
    ts = Time.current.to_i.to_s
    signature = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', SECRET, "v0:#{ts}:#{raw}")}"
    post path, params: raw, headers: { "X-Slack-Request-Timestamp" => ts, "X-Slack-Signature" => signature,
                                       "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
  end

  def interaction(payload) = signed_post(slack_interactions_webhook_path, payload: payload.to_json)

  def shortcut
    interaction(type: "message_action", callback_id: "run_workflow", trigger_id: "tr1", team: { id: "T1" },
                user: { id: "U1" }, channel: { id: "C1" },
                message: { ts: "1700000000.000100", text: "Customer Acme asks for the Q3 digest" })
  end

  def submission(view)
    interaction(type: "view_submission", team: { id: "T1" }, user: { id: "U1" },
                view: { id: "V1", callback_id: "run_workflow", private_metadata: view["private_metadata"],
                        state: { values: { workflow: { workflow: { selected_option: { value: "#{@project.id}:#{@workflow.id}" } } },
                                           notes: { notes: { value: "for the board" } } } } })
  end

  test "a request Slack did not sign is refused" do
    post slack_interactions_webhook_path, params: { payload: "{}" }

    assert_response :unauthorized
  end

  test "a person not linked yet is shown the link instead of the workflows" do
    shortcut

    assert_response :ok
    button = fake_slack.last_opened_view.dig("blocks", 1, "elements", 0)
    claim = Slack::AccountLink.claim(URI.parse(button["url"]).path.split("/").last)
    assert_equal [ "T1", "U1" ], claim.values_at("team", "user")
  end

  test "the shortcut's modal starts the workflow as the linked person, in that message's thread" do
    link!
    shortcut
    view = fake_slack.last_opened_view
    assert_equal [ "Weekly Digest — Sales Ops" ], view.dig("blocks", 0, "element", "options").map { |o| o.dig("text", "text") }
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    WorkflowService.expects(:enqueue).with(has_entries(
      user: @user, shared_context: has_entries("chat" => has_entries(
        "provider" => "slack", "thread_id" => "1700000000.000100",
        "text" => "Customer Acme asks for the Q3 digest\n\nNotes: for the board"
      ))
    )).once.returns(run)
    WorkflowService.stubs(:dispatch_or_leave_to_relay)

    submission(view)

    assert_response :ok
    assert_equal({}, response.parsed_body)
    dispatch = TriggerDispatch.find_by!(workflow_run: run)
    assert Chat::RunStatusReporter.applies?(dispatch, "running")
  end

  test "/aixle run opens the modal and the run opens its own thread; a refused start takes it back" do
    link!
    signed_post(slack_commands_webhook_path, command: "/aixle", text: "run", team_id: "T1", user_id: "U1",
                                             channel_id: "C1", trigger_id: "tr2")
    view = fake_slack.last_opened_view
    WorkflowService.expects(:enqueue).returns(WorkflowRun.new)

    submission(view)

    opening = fake_slack.posted_messages.sole
    assert_equal [ "C1", ":arrow_forward: <@U1> started *Weekly Digest*" ], opening.values_at(:channel, :text)
    assert_equal opening[:ts], fake_slack.last_deleted_message[:ts]
    assert_match(/Weekly Digest did not start/, response.parsed_body.dig("errors", "workflow"))
  end

  test "/aixle status lists, only to the asker, the runs started in the channel" do
    link!
    create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, shared_context: {
      "chat" => { "provider" => "slack", "conversation" => { "id" => "C1", "type" => "channel" } }
    })

    signed_post(slack_commands_webhook_path, command: "/aixle", text: "status", team_id: "T1", user_id: "U1", channel_id: "C1")

    assert_equal "ephemeral", response.parsed_body["response_type"]
    assert_includes response.parsed_body.dig("blocks", 0, "text", "text"), ":arrow_forward: Running — *Weekly Digest*"
  end
end
