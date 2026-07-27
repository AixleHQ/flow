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
      scope: @project
    )
    assert agent.valid?
  end

  test "company scope is rejected (agents are project-only)" do
    agent = Agent.new(name: "test_agent", title: "Test", persona: "Test", scope: @company)
    refute_predicate agent, :valid?
    assert_includes agent.errors[:scope_type], "is not included in the list"
  end

  test "invalid without name" do
    agent = Agent.new(title: "Test", persona: "Test", scope: @project)
    refute_predicate agent, :valid?
    assert agent.errors[:name].present?
  end

  test "name is converted to lowercase automatically" do
    agent = Agent.new(name: "TestAgent", title: "Test", persona: "Test", scope: @project)
    # Name is auto-downcased, so validation passes
    assert agent.valid?
    assert_equal "testagent", agent.name
  end

  test "invalid with name starting with number" do
    agent = Agent.new(name: "1agent", title: "Test", persona: "Test", scope: @project)
    refute_predicate agent, :valid?
  end

  test "name is auto-downcased and sanitized" do
    agent = Agent.new
    agent.name = "Test Agent!@#"
    assert_equal "test_agent___", agent.name
  end

  test "name uniqueness is scoped" do
    project2 = create(:project, company: @company, owner: @owner)
    Agent.create!(name: "shared", title: "T1", persona: "P1", scope: @project)

    # Same name in a different scope (another project) is OK
    agent_other = Agent.new(name: "shared", title: "T2", persona: "P2", scope: project2)
    assert agent_other.valid?

    # Same name in same scope is NOT OK
    agent_dup = Agent.new(name: "shared", title: "T3", persona: "P3", scope: @project)
    refute_predicate agent_dup, :valid?
    assert agent_dup.errors[:name].any? { |e| e.include?("already exists") }
  end

  # == Scopes ==

  test "belonging_to_company returns agents of all the company projects" do
    project2 = create(:project, company: @company, owner: @owner)
    other_company = create(:company, email_domain: "other-agent.com")
    other_owner = create(:user, company: other_company)
    other_project = create(:project, company: other_company, owner: other_owner)

    a1 = Agent.create!(name: "a1", title: "A1", persona: "P", scope: @project)
    a2 = Agent.create!(name: "a2", title: "A2", persona: "P", scope: project2)
    foreign = Agent.create!(name: "foreign", title: "F", persona: "P", scope: other_project)

    result = Agent.belonging_to_company(@company)

    assert_includes result, a1
    assert_includes result, a2
    refute_includes result, foreign
  end

  test "for_project returns only that project's agents" do
    project2 = create(:project, company: @company, owner: @owner)
    mine = Agent.create!(name: "mine", title: "M", persona: "P", scope: @project)
    other = Agent.create!(name: "other", title: "O", persona: "P", scope: project2)

    result = Agent.for_project(@project)

    assert_includes result, mine
    refute_includes result, other
  end

  # == visible_for_project ==

  test "visible_for_project returns only that project's agents" do
    project2 = create(:project, company: @company, owner: @owner)
    Agent.create!(name: "mine_agent", title: "M", persona: "P", scope: @project)
    Agent.create!(name: "other_agent", title: "O", persona: "P", scope: project2)

    result = Agent.visible_for_project(@project)
    names = result.pluck(:name)

    assert_includes names, "mine_agent"
    refute_includes names, "other_agent"
  end

  test "visible_for_project returns ActiveRecord::Relation" do
    result = Agent.visible_for_project(@project)
    assert_kind_of ActiveRecord::Relation, result
  end

  # == scope_indicator ==

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
