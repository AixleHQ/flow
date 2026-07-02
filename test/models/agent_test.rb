# frozen_string_literal: true

require "test_helper"

class AgentTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  # == Validations ==

  test "valid with all required fields" do
    agent = Agent.new(
      name: "test_agent",
      title: "Test Agent",
      persona: "You are a helpful assistant",
      scope: @company
    )
    assert agent.valid?
  end

  test "invalid without name" do
    agent = Agent.new(title: "Test", persona: "Test", scope: @company)
    refute_predicate agent, :valid?
    assert agent.errors[:name].present?
  end

  test "name is converted to lowercase automatically" do
    agent = Agent.new(name: "TestAgent", title: "Test", persona: "Test", scope: @company)
    # Name is auto-downcased, so validation passes
    assert agent.valid?
    assert_equal "testagent", agent.name
  end

  test "invalid with name starting with number" do
    agent = Agent.new(name: "1agent", title: "Test", persona: "Test", scope: @company)
    refute_predicate agent, :valid?
  end

  test "name is auto-downcased and sanitized" do
    agent = Agent.new
    agent.name = "Test Agent!@#"
    assert_equal "test_agent___", agent.name
  end

  test "name uniqueness is scoped" do
    Agent.create!(name: "shared", title: "T1", persona: "P1", scope: @company)

    # Same name in different scope is OK
    agent_project = Agent.new(name: "shared", title: "T2", persona: "P2", scope: @project)
    assert agent_project.valid?

    # Same name in same scope is NOT OK
    agent_dup = Agent.new(name: "shared", title: "T3", persona: "P3", scope: @company)
    refute_predicate agent_dup, :valid?
    assert agent_dup.errors[:name].any? { |e| e.include?("already exists") }
  end

  # == Scopes ==

  test "for_company returns company agents" do
    company_agent = Agent.create!(name: "company_agent", title: "CA", persona: "P", scope: @company)
    project_agent = Agent.create!(name: "project_agent", title: "PA", persona: "P", scope: @project)

    result = Agent.for_company(@company)

    assert_includes result, company_agent
    refute_includes result, project_agent
  end

  test "for_project returns project agents" do
    company_agent = Agent.create!(name: "company_agent", title: "CA", persona: "P", scope: @company)
    project_agent = Agent.create!(name: "project_agent", title: "PA", persona: "P", scope: @project)

    result = Agent.for_project(@project)

    assert_includes result, project_agent
    refute_includes result, company_agent
  end

  # == visible_for_project ==

  test "visible_for_project returns company and project agents" do
    Agent.create!(name: "company_only", title: "CO", persona: "P", scope: @company)
    Agent.create!(name: "project_only", title: "PO", persona: "P", scope: @project)

    result = Agent.visible_for_project(@project)
    names = result.pluck(:name)

    assert_includes names, "company_only"
    assert_includes names, "project_only"
  end

  test "visible_for_project includes both company and project when same name" do
    Agent.create!(name: "shared", title: "Company", persona: "P", scope: @company)
    Agent.create!(name: "shared", title: "Project", persona: "P", scope: @project)

    result = Agent.visible_for_project(@project)
    shared = result.where(name: "shared")

    assert_equal 2, shared.count
  end

  test "visible_for_project returns ActiveRecord::Relation" do
    result = Agent.visible_for_project(@project)
    assert_kind_of ActiveRecord::Relation, result
  end

  # == scope_indicator ==

  test "#scope_indicator returns 'company' for company agent" do
    agent = Agent.new(scope_type: "Company")
    assert_equal "company", agent.scope_indicator
  end

  test "#scope_indicator returns 'project' for project agent" do
    agent = Agent.new(scope_type: "Project")
    assert_equal "project", agent.scope_indicator
  end

  # == to_system_prompt ==

  test "to_system_prompt includes title and persona" do
    agent = Agent.new(title: "My Agent", persona: "You are helpful")

    prompt = agent.to_system_prompt

    assert_includes prompt, "# My Agent"
    assert_includes prompt, "You are helpful"
  end

  test "to_system_prompt includes communication_style when present" do
    agent = Agent.new(
      title: "Agent",
      persona: "You are helpful",
      communication_style: "Be concise"
    )

    prompt = agent.to_system_prompt

    assert_includes prompt, "## Communication Style"
    assert_includes prompt, "Be concise"
  end

  test "to_system_prompt includes principles when present" do
    agent = Agent.new(
      title: "Agent",
      persona: "You are helpful",
      principles: "Always be honest"
    )

    prompt = agent.to_system_prompt

    assert_includes prompt, "## Principles"
    assert_includes prompt, "Always be honest"
  end

  test "to_system_prompt omits empty sections" do
    agent = Agent.new(title: "Agent", persona: "Test")

    prompt = agent.to_system_prompt

    refute_includes prompt, "Communication Style"
    refute_includes prompt, "Principles"
  end

  # == Ransack ==

  test "ransackable_attributes returns expected fields" do
    attrs = Agent.ransackable_attributes

    assert_includes attrs, "name"
    assert_includes attrs, "title"
    assert_includes attrs, "source"
  end

  test "ransackable_associations returns scope" do
    assocs = Agent.ransackable_associations

    assert_includes assocs, "scope"
  end
end
