# frozen_string_literal: true

require "test_helper"

class Trackers::Jira::PersonalDataTest < ActiveSupport::TestCase
  REPORT_URL = "https://api.atlassian.com/app/report-accounts/"
  ADA = "557058:ada"

  setup do
    with_jira_oauth_app
    @integration = create(:integration, :jira_oauth, :active)
  end

  def remember(*ids) = TrackerAccount.remember!(provider: "jira", account_ids: ids)

  test "the ids Aixle keeps are reported, and a report with nothing to do marks them reported" do
    remember(ADA, "557058:alan")
    stub_request(:post, REPORT_URL)
      .with(headers: { "Authorization" => "Bearer jira-token" },
            body: hash_including("accounts" => [ hash_including("accountId" => ADA), hash_including("accountId" => "557058:alan") ]))
      .to_return(status: 204, headers: { "Cycle-Period" => "604800" })

    counts = Trackers::Jira::PersonalDataReporter.new.run

    assert_equal 2, counts[:reported]
    assert TrackerAccount.all.all? { |a| a.reported_at.present? }
    assert_empty TrackerAccount.due(7.days)
  end

  test "an account Atlassian reports closed is erased everywhere Aixle keeps it" do
    remember(ADA)
    project = @integration.project
    event = TriggerEvent.create!(project: project, event_type: "tracker.issue.assigned", source: "tracker", dedup_key: "k1", data: {
      "actor" => { "id" => ADA, "name" => "Ada Lovelace", "is_me" => false },
      "change" => { "field" => "assignee", "from" => nil, "to" => "Ada Lovelace", "to_id" => ADA },
      "issue" => { "id" => "10100", "key" => "ENG-1" }
    })
    @integration.update!(settings: @integration.settings.merge("tracker_identity" => { "id" => ADA, "name" => "Ada" },
                                                               "identity_display_name" => "Ada"))
    delivery = TrackerDelivery.record(subscription: create(:tracker_subscription, integration: @integration), dedup_key: "d",
                                      notifications: [ Trackers::Notification.build(kind: :issue_updated, scope_id: "10000", issue_id: "1", actor: { id: ADA }) ])
    stub_request(:post, REPORT_URL).to_return(status: 200, body: { accounts: [ { accountId: ADA, status: "closed" } ] }.to_json)

    assert_equal 1, Trackers::Jira::PersonalDataReporter.new.run[:closed]

    data = event.reload.data
    assert_equal({ "id" => nil, "name" => "Former user", "is_me" => false }, data["actor"])
    assert_equal({ "field" => "assignee", "from" => nil, "to" => "Former user", "to_id" => nil }, data["change"])
    assert_equal({ "id" => "10100", "key" => "ENG-1" }, data["issue"])
    assert_nil @integration.reload.settings["tracker_identity"]
    assert_nil TrackerDelivery.find_by(id: delivery.id)
    assert TrackerAccount.find_by(account_id: ADA).closed?
  end

  test "without the OAuth app, or a 3LO connection to report with, nothing is sent" do
    remember(ADA)
    @integration.update!(status: :error)
    assert_equal "no_token", Trackers::Jira::PersonalDataReporter.new.run[:skipped]

    with_jira_oauth_app(client_id: "", client_secret: "")
    assert_equal "no_oauth_app", Trackers::Jira::PersonalDataReporter.new.run[:skipped]
    assert_not_requested :post, REPORT_URL
  end

  test "a throttled report is left for the next run" do
    remember(ADA)
    stub_request(:post, REPORT_URL).to_return(status: 429, headers: { "Retry-After" => "60" })

    assert_equal 0, Trackers::Jira::PersonalDataReporter.new.run[:reported]
    assert_nil TrackerAccount.sole.reported_at
  end

  test "an event's actor and an assignment are remembered as they come in" do
    jira = stub_jira!
    Trackers::Provisioning.ensure_for!(@integration)
    create(:trigger_binding, project: @integration.project, workflow: create(:workflow, scope: @integration.project),
                             created_by: @integration.project.owner, event_type: "tracker.issue.assigned")
    WorkflowService.stubs(:enqueue).returns(build(:workflow_run))
    notification = Trackers::Notification.build(kind: :issue_updated, scope_id: "10000", issue_id: "10100", revision: "5",
                                                actor: { id: "557058:alan", name: "Alan" },
                                                changes: [ { field: "assignee", to: "Ada Lovelace", to_id: ADA } ])

    Trackers::EventPipeline.new(@integration).process(notification)
    Trackers::Provider.for(@integration).assign_issue("10000", "ENG-1", FakeJira::Api::BOT_ID)

    assert_equal [ "557058:alan", ADA, FakeJira::Api::BOT_ID ].sort, TrackerAccount.pluck(:account_id).sort
    assert jira.called?(:assign)
  end
end
