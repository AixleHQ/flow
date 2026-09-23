# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaListAgentsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
  end

  test "lists project-scoped agents visible for the session's project" do
    first_agent = create(:agent, scope: @project, name: "first_helper", title: "First Helper")
    second_agent = create(:agent, scope: @project, name: "second_helper", title: "Second Helper")

    # Agents that must NOT show up for this project
    other_company = create(:company)
    other_company_project = create(:project, company: other_company, owner: create(:user, company: other_company))
    create(:agent, scope: other_company_project, name: "foreign_company_agent")
    other_project = create(:project, company: @company, owner: @user)
    create(:agent, scope: other_project, name: "sibling_project_agent")

    result = InternalTools::MetaListAgents.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    assert_equal "", result[:stderr]

    data = JSON.parse(result[:stdout])
    assert_equal 2, data["agents_count"]
    assert_equal data["agents_count"], data["agents"].size

    by_id = data["agents"].index_by { |a| a["id"] }
    assert_equal %w[first_helper second_helper].sort,
                 data["agents"].map { |a| a["name"] }.sort

    assert_equal "First Helper", by_id[first_agent.id]["title"]
    assert_equal "Project", by_id[first_agent.id]["scope_type"]
    assert_equal "Second Helper", by_id[second_agent.id]["title"]
    assert_equal "Project", by_id[second_agent.id]["scope_type"]

    # Foreign agents are excluded
    listed_names = data["agents"].map { |a| a["name"] }
    assert_not_includes listed_names, "foreign_company_agent"
    assert_not_includes listed_names, "sibling_project_agent"
  end

  test "refuses a project_id other than the session's project" do
    other_project = create(:project, company: @company, owner: @user)

    error = assert_raises(InternalTools::WorkflowContextError) do
      InternalTools::MetaListAgents.new(params: { project_id: other_project.id }, session: @session).execute
    end
    assert_match(/act only on this session's project/, error.message)
  end

  test "returns success with an empty list when no agents are visible" do
    result = InternalTools::MetaListAgents.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal 0, data["agents_count"]
    assert_equal [], data["agents"]
  end
end
