# frozen_string_literal: true

require "test_helper"

# One Slack workspace connected by two companies as peers
# (docs/design/shared-chat-workspaces.md §10): a message reaches only the
# companies that connected its channel, each through an event of its own.
class Chat::WorkspaceRouterTest < ActiveJob::TestCase
  setup do
    stub_slack_client!.channel_names = { "C0NEWCHAN1" => "newchan" }
    @acme = company_with_slack("Acme")
    @globex = company_with_slack("Globex")
    @endpoint = WebhookEndpoint.find_by!(slug: "slack-team-T1")
  end

  # A company, an owner, a project with an unattended workflow, and its own
  # install of the shared workspace T1.
  def company_with_slack(name)
    owner = create(:user, :with_company)
    company = owner.companies.first
    company.update!(name: name)
    project = create(:project, owner: owner, company: company, name: "#{name} ops")
    workflow = create(:workflow, scope: project, name: "#{name} deploy")
    create(:step, workflow: workflow, allow_non_interactive: true)
    fake_slack.team_id = "T1"
    install = Slack::IntegrationService.new(company: company, connected_by: owner).create_from_oauth(code: SecureRandom.hex)
    { company: company, owner: owner, project: project, workflow: workflow, install: install }
  end

  def trigger_for(tenant, channel, **attrs)
    create(:trigger_binding, project: tenant[:project], workflow: tenant[:workflow], created_by: tenant[:owner],
                             chat_channel: nil, enabled: false, **attrs).tap do |binding|
      binding.update!(enabled: true, chat_conversation: connect_chat_channel(company: tenant[:company], integration: tenant[:install],
                                                                             external_id: channel, name: channel.downcase))
    end
  end

  def mention(text, channel:, key: SecureRandom.hex)
    received = ReceivedWebhook.create!(webhook_endpoint: @endpoint, idempotency_key: key, event_type: "slack", raw_payload: {
      "type" => "event_callback", "event_id" => key, "team_id" => "T1",
      "event" => { "type" => "app_mention", "channel" => channel, "user" => "U0PERSON1", "text" => "<@U0BOTFAKE0> #{text}",
                   "ts" => "5.5" }
    })
    Webhooks::ProcessEventJob.perform_now(received.id)
  end

  def create_outsider_in(tenant)
    user = create(:user, :employee, company: tenant[:company])
    tenant[:project].add_collaborator(user)
    user
  end

  test "the companies share one workspace, and its endpoint hears through the first install" do
    assert_equal @acme[:install].chat_workspace, @globex[:install].chat_workspace
    assert_equal @acme[:install].id, @endpoint.config["integration_id"]
  end

  test "a message reaches each company that connected its channel, as an event of its own, and no other" do
    acme = trigger_for(@acme, "C0SHARED01")
    globex = trigger_for(@globex, "C0SHARED01")
    trigger_for(@globex, "C0GLOBEX01")
    fired = []
    WorkflowService.stubs(:enqueue).with { |**args| fired << args[:project] }.returns(build(:workflow_run))

    mention("deploy", channel: "C0SHARED01", key: "Ev1")

    assert_equal [ @acme[:project], @globex[:project] ].sort_by(&:id), fired.sort_by(&:id)
    events = TriggerEvent.where(event_type: Chat::EVENT_TYPE).order(:company_id)
    assert_equal [ @acme[:company].id, @globex[:company].id ].sort, events.map(&:company_id)
    assert_equal [ "slack:Ev1:c#{@acme[:company].id}", "slack:Ev1:c#{@globex[:company].id}" ].sort, events.map(&:dedup_key).sort
    assert_equal({ @acme[:company].id => @acme[:install].id, @globex[:company].id => @globex[:install].id },
                 events.to_h { |e| [ e.company_id, e.data["integration_id"] ] })
    assert_equal [ acme.id, globex.id ].sort, TriggerDispatch.pluck(:trigger_binding_id).sort
  end

  test "a channel only one company connected is that company's alone" do
    trigger_for(@globex, "C0GLOBEX01")
    WorkflowService.expects(:enqueue).once.with(has_entries(project: @globex[:project])).returns(build(:workflow_run))

    mention("deploy", channel: "C0GLOBEX01")

    assert_equal [ @globex[:company].id ], TriggerEvent.pluck(:company_id)
  end

  test "help is answered once, naming each company, and lists only what listens in that channel" do
    trigger_for(@acme, "C0SHARED01", filter_predicate: { "text" => "ship" })
    trigger_for(@globex, "C0SHARED01", filter_predicate: { "text" => "release" })
    trigger_for(@globex, "C0GLOBEX01", filter_predicate: { "text" => "secret" })

    mention("/help", channel: "C0SHARED01")

    replies = fake_slack.posted_messages.select { |m| m[:channel] == "C0SHARED01" }
    assert_equal 1, replies.size
    text = replies.sole[:text]
    assert_includes text, "_[Acme]_"
    assert_includes text, "_[Globex]_"
    assert_not_includes text, "ops", "projects are not named where guests may read"
    assert_not_includes text, "secret"
    assert_equal 0, TriggerEvent.count
  end

  test "a code either company asked for connects the channel to that company only" do
    _record, code = ChatConnectCode.issue!(project: @globex[:project], provider: "slack", user: @globex[:owner], channel: "newchan")

    mention("connect #{code}", channel: "C0NEWCHAN1")

    connection = ChatChannelConnection.sole
    assert_equal [ @globex[:company], @globex[:install].chat_workspace ],
                 [ connection.company, connection.chat_conversation.chat_workspace ]
    assert_match(%r{\Ahttps://fake-workspace\.slack\.com/archives/C0NEWCHAN1/p}, connection.confirmation_url)
  end

  test "one company's agent leaves another's bot messages alone in a channel they share" do
    acme_trigger = trigger_for(@acme, "C0SHARED01")
    trigger_for(@globex, "C0SHARED01")
    run = create(:workflow_run, workflow: @acme[:workflow], project: @acme[:project], user: @acme[:owner])
    session = create(:terminal_session, :running, :agent_session, user: @acme[:owner], project: @acme[:project],
                                                                  mode: "non_interactive", initial_prompt: "x")
    create(:step_run, workflow_run: run, step: @acme[:workflow].steps.first, terminal_session: session)
    globex_message = "1700000000.000900"
    ChatMessage.record!(conversation: acme_trigger.chat_conversation, message_id: globex_message,
                        company_id: @globex[:company].id)

    posted = InternalTools::ChatPostMessage.new(params: { provider: "slack", conversation: "C0SHARED01", text: "ours" },
                                                session: session.reload).execute
    own = JSON.parse(posted[:stdout])["message_id"]
    edit = ->(id) { InternalTools::ChatUpdateMessage.new(params: { provider: "slack", conversation: "C0SHARED01", message_id: id, text: "x" }, session: session).execute }

    assert_equal 0, edit.call(own)[:exit_code]
    refused = edit.call(globex_message)
    assert_equal 1, refused[:exit_code]
    assert_match(/was not posted for Acme/, refused[:stderr])
    assert_equal [ own ], fake_slack.updated_messages.pluck(:ts)
  end

  test "a person in both companies picks among both companies' workflows from Slack" do
    person = @acme[:owner]
    person.company_memberships.create!(company: @globex[:company], role: "employee", state: "active", accepted_at: Time.current)
    @globex[:project].add_collaborator(person)

    titles = Chat::RunCatalog.entries(person, @acme[:install]).map(&:title)

    assert_includes titles, "Acme deploy — Acme ops (Acme)"
    assert_includes titles, "Globex deploy — Globex ops (Globex)"
    assert_equal [ "Acme deploy — Acme ops" ], Chat::RunCatalog.entries(create_outsider_in(@acme), @acme[:install]).map(&:title)
  end
end
