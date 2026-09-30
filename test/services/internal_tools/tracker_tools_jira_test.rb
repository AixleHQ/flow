# frozen_string_literal: true

require "test_helper"

# The tracker tools over a Jira connection, through the real provider.
class InternalTools::TrackerToolsJiraTest < ActiveSupport::TestCase
  setup do
    @jira = stub_jira!
    @integration = create(:integration, :jira, :active)
    Trackers::Provisioning.ensure_for!(@integration)
    @project = @integration.project
    @user = create(:user, company: @project.company)
    @session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                      mode: "non_interactive", initial_prompt: "work")
  end

  def run_tool(klass, **params)
    result = klass.new(params: params, session: @session).execute
    assert_equal 0, result[:exit_code], result[:stderr]
    JSON.parse(result[:stdout])
  end

  test "the connection's projects are its trackers, the first one primary" do
    trackers = run_tool(InternalTools::TrackerList)["trackers"]

    assert_equal [ [ "engineering", "jira", true ], [ "operations", "jira", false ] ],
                 trackers.map { |t| t.values_at("handle", "provider", "primary") }
  end

  test "an issue URL picks its tracker, and the agent moves it by column name" do
    moved = run_tool(InternalTools::TrackerTransitionIssue, issue: "https://acme.atlassian.net/browse/ENG-1", status: "Doing")

    assert_equal [ "ENG-1", "Doing", "In Progress" ], [ moved["key"], moved.dig("status", "name"), moved.dig("fields", "state") ]
    operation = TrackerOperation.sole
    assert_equal [ "engineering", { "field" => "status", "to" => "Doing" } ], [ operation.project_tracker.handle, operation.change ]
  end

  test "tracker_list_users finds who an issue can be assigned to" do
    users = run_tool(InternalTools::TrackerListUsers, query: "ada lovelace")["users"]

    assert_equal [ { "id" => "557058:ada", "name" => "Ada Lovelace" } ], users
  end
end
