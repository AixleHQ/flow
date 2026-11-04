# frozen_string_literal: true

require "test_helper"

# Which Slack channels the chat_* tools reach: the thread a run came from, and
# channels connected to the project's company — nothing an agent merely names.
class InternalTools::ChatSlackChannelsTest < ActiveSupport::TestCase
  setup do
    stub_slack_client!
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @slack = Integration.create!(provider: :slack, company: @company, project: nil, connected_by: @user, name: "Acme",
                                 status: :active, settings: { "team_id" => "T1" })
    @slack.update!(credentials_data: { "bot_token" => "xoxb-acme" })
    @reports = connect_chat_channel(company: @company, integration: @slack, external_id: "C0REPORTS1", name: "reports")
  end

  def session_for(shared_context)
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user, shared_context: shared_context)
    step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow))
    session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                                                                  mode: "non_interactive", initial_prompt: "x")
    step_run.update!(terminal_session: session)
    session.reload
  end

  def slack_origin(channel)
    { "chat" => { "provider" => "slack", "integration_id" => @slack.id, "workspace_id" => "T1",
                  "conversation" => { "id" => channel, "type" => "channel" }, "thread_id" => "9.9" } }
  end

  def post_message(session, **params)
    InternalTools::ChatPostMessage.new(params: { provider: "slack", text: "hi" }.merge(params), session: session).execute
  end

  test "a run answers in the thread it came from, even in a channel nobody connected" do
    session = session_for(slack_origin("C0ELSEWHR1"))

    result = post_message(session)

    assert_equal 0, result[:exit_code], result[:stderr]
    assert_equal [ "C0ELSEWHR1", "9.9", "xoxb-acme" ], fake_slack.last_posted_message.values_at(:channel, :thread_ts, :token)
  end

  test "a connected channel is reached by its name or id, an unconnected one never, whatever the agent names" do
    session = session_for({})
    foreign = connect_chat_channel(company: create(:company), external_id: "C0FOREIGN1", name: "secret")

    assert_equal 0, post_message(session, conversation: "#reports")[:exit_code]
    assert_equal 0, post_message(session, conversation: "C0REPORTS1")[:exit_code]
    assert_equal [ "C0REPORTS1" ] * 2, fake_slack.posted_messages.pluck(:channel)

    [ foreign.external_id, "#secret", "C0UNKNOWN1" ].each do |value|
      result = post_message(session, conversation: value)
      assert_equal 1, result[:exit_code]
      assert_match(/is not a Slack channel connected to #{Regexp.escape(@company.name)}\. Connected: #reports\./, result[:stderr])
    end
    assert_equal 2, fake_slack.posted_messages.size, "a refused channel never reaches Slack"
  end

  test "a channel name two connected workspaces share is reached through its workspace, through that workspace's install" do
    ops = Integration.create!(provider: :slack, company: @company, project: nil, connected_by: @user, name: "Ops",
                              status: :active, settings: { "team_id" => "T2", "team_name" => "Ops" })
    ops.update!(credentials_data: { "bot_token" => "xoxb-ops" })
    connect_chat_channel(company: @company, integration: ops, external_id: "C0OPSREP1", name: "reports")
    @slack.chat_workspace.update!(name: "Acme")
    session = session_for({})

    ambiguous = post_message(session, conversation: "#reports")
    assert_equal 1, ambiguous[:exit_code]
    assert_match(/"#reports" names a Slack channel in more than one workspace .* — name it as Workspace\/#channel\. /,
                 ambiguous[:stderr])
    assert_match(/Connected: Acme\/#reports, Ops\/#reports\./, ambiguous[:stderr])

    assert_equal 0, post_message(session, conversation: "Ops/#reports")[:exit_code]
    assert_equal 0, post_message(session, conversation: "acme/reports")[:exit_code]
    assert_equal [ %w[C0OPSREP1 xoxb-ops], %w[C0REPORTS1 xoxb-acme] ],
                 fake_slack.posted_messages.map { |m| m.values_at(:channel, :token) }
  end

  test "reading, editing and deleting are confined the same way" do
    session = session_for({})

    read = InternalTools::ChatReadThread.new(params: { provider: "slack", conversation: "C0FOREIGN1", thread: "1.1" },
                                             session: session).execute
    edit = InternalTools::ChatUpdateMessage.new(params: { provider: "slack", conversation: "C0FOREIGN1", message_id: "1.1",
                                                          text: "x" }, session: session).execute
    delete = InternalTools::ChatDeleteMessage.new(params: { provider: "slack", conversation: "C0FOREIGN1", message_id: "1.1" },
                                                  session: session).execute

    assert_equal [ 1, 1, 1 ], [ read, edit, delete ].pluck(:exit_code)
    assert_empty fake_slack.replies_reads + fake_slack.updated_messages + fake_slack.deleted_messages
  end
end
