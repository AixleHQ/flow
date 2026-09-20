# frozen_string_literal: true

require "test_helper"

class InternalTools::YoutrackUpdateIssueTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    owner = create(:user, company: company)
    project = create(:project, company: company, owner: owner)
    integration = create(:integration, :active, provider: :youtrack, company: company, project: project,
      settings: { "base_url" => "https://youtrack.example.com", "youtrack_project_id" => "0-1" })
    integration.credentials_data = { permanent_token: "perm:secret" }
    integration.save!
    @session = Struct.new(:project, :step_run).new(project, nil)
    UrlSafetyValidator.stubs(:resolved_addresses).returns([ IPAddr.new("93.184.216.34") ])
  end

  test "rejects a project-changing update before calling YouTrack" do
    result = tool(changes: { project: { id: "0-2" } }).execute
    assert_equal 1, result[:exit_code]
    assert_match(/Only summary/, result[:stderr])
  end

  test "rejects an update response outside the selected project" do
    stub_request(:get, %r{https://youtrack.example.com/api/issues/APP-1})
      .to_return(status: 200, body: { id: "2-1", project: { id: "0-1" } }.to_json)
    stub_request(:post, %r{https://youtrack.example.com/api/issues/APP-1})
      .to_return(status: 200, body: { id: "2-1", project: { id: "0-2" } }.to_json)

    result = tool(changes: { summary: "Updated" }).execute
    assert_equal 1, result[:exit_code]
    assert_match(/outside the connected project/, result[:stderr])
  end

  private

  def tool(changes:)
    InternalTools::YoutrackUpdateIssue.new(params: { issue_id: "APP-1", changes: changes }, session: @session)
  end
end
