# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaListAgentsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
  end

  test "lists company- and project-scoped agents visible for the session's project" do
    company_agent = create(:agent, scope: @company, name: "company_helper", title: "Company Helper")
    project_agent = create(:agent, scope: @project, name: "project_helper", title: "Project Helper")

    # Agents that must NOT show up for this project
    other_company = create(:company)
    create(:agent, scope: other_company, name: "foreign_company_agent")
    other_project = create(:project, company: @company, owner: @user)
    create(:agent, scope: other_project, name: "sibling_project_agent")

    result = InternalTools::MetaListAgents.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    assert_equal "", result[:stderr]

    data = JSON.parse(result[:stdout])
    assert_equal 2, data["agents_count"]
    assert_equal data["agents_count"], data["agents"].size

    by_id = data["agents"].index_by { |a| a["id"] }
    assert_equal %w[company_helper project_helper].sort,
                 data["agents"].map { |a| a["name"] }.sort

    assert_equal "Company Helper", by_id[company_agent.id]["title"]
    assert_equal "Company", by_id[company_agent.id]["scope_type"]
    assert_equal "Project Helper", by_id[project_agent.id]["title"]
    assert_equal "Project", by_id[project_agent.id]["scope_type"]

    # Foreign agents are excluded
    listed_names = data["agents"].map { |a| a["name"] }
    assert_not_includes listed_names, "foreign_company_agent"
    assert_not_includes listed_names, "sibling_project_agent"
  end

  test "targets an explicit project via project_id param instead of the session project" do
    # Session project has its own project-scoped agent...
    create(:agent, scope: @project, name: "session_project_agent")
    # ...but we ask about a different project in the same company.
    other_project = create(:project, company: @company, owner: @user)
    target_agent = create(:agent, scope: other_project, name: "target_project_agent")
    shared_company_agent = create(:agent, scope: @company, name: "shared_company_agent")

    result = InternalTools::MetaListAgents.new(
      params: { project_id: other_project.id },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])

    listed_ids = data["agents"].map { |a| a["id"] }
    assert_includes listed_ids, target_agent.id
    assert_includes listed_ids, shared_company_agent.id
    # The session project's own agent is not part of the targeted project's view.
    assert_not_includes data["agents"].map { |a| a["name"] }, "session_project_agent"
    assert_equal 2, data["agents_count"]
  end

  test "returns success with an empty list when no agents are visible" do
    result = InternalTools::MetaListAgents.new(params: {}, session: @session).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal 0, data["agents_count"]
    assert_equal [], data["agents"]
  end
end
