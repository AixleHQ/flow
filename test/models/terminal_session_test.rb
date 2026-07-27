# frozen_string_literal: true

require "test_helper"

class TerminalSessionTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  # == session_config JSONB (config_files & env_vars only) ==

  test "valid with empty session_config" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert session.valid?
  end

  test "config_files returns config_files hash" do
    session = build(:terminal_session, user: @user, session_config: {
      "config_files" => { "CLAUDE.md" => "# Context" }
    })
    assert_equal({ "CLAUDE.md" => "# Context" }, session.config_files)
  end

  test "config_files returns empty hash when absent" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert_equal({}, session.config_files)
  end

  test "env_vars returns env_vars hash" do
    session = build(:terminal_session, user: @user, session_config: {
      "env_vars" => { "KEY" => "value" }
    })
    assert_equal({ "KEY" => "value" }, session.env_vars)
  end

  test "env_vars returns empty hash when absent" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert_equal({}, session.env_vars)
  end

  # == BMAD config helpers ==

  test "bmad_enabled? returns true when bmad_enabled is true" do
    session = build(:terminal_session, user: @user, session_config: { "bmad_enabled" => true })
    assert session.bmad_enabled?
  end

  test "bmad_enabled? returns false when bmad_enabled is false" do
    session = build(:terminal_session, user: @user, session_config: { "bmad_enabled" => false })
    assert_not session.bmad_enabled?
  end

  test "bmad_enabled? returns false when bmad_enabled is absent" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert_not session.bmad_enabled?
  end

  test "bmad_enabled? returns false when session_config is nil" do
    session = build(:terminal_session, user: @user, session_config: nil)
    assert_not session.bmad_enabled?
  end

  test "bmad_enabled? returns false for non-boolean truthy values" do
    session = build(:terminal_session, user: @user, session_config: { "bmad_enabled" => "true" })
    assert_not session.bmad_enabled?
  end

  test "bmad_modules returns default modules when not specified" do
    session = build(:terminal_session, user: @user, session_config: { "bmad_enabled" => true })
    assert_equal %w[bmm bmb cis wds], session.bmad_modules
  end

  test "bmad_modules returns custom modules when specified" do
    session = build(:terminal_session, user: @user, session_config: {
      "bmad_enabled" => true,
      "bmad_modules" => %w[bmm cis bmb]
    })
    assert_equal %w[bmm cis bmb], session.bmad_modules
  end

  test "bmad_modules returns default when session_config is nil" do
    session = build(:terminal_session, user: @user, session_config: nil)
    assert_equal %w[bmm bmb cis wds], session.bmad_modules
  end

  test "bmad_modules returns default when bmad_modules key is absent" do
    session = build(:terminal_session, user: @user, session_config: {})
    assert_equal %w[bmm bmb cis wds], session.bmad_modules
  end

  test "BMAD_DEFAULT_MODULES constant is frozen" do
    assert TerminalSession::BMAD_DEFAULT_MODULES.frozen?
    assert_equal %w[bmm bmb cis wds], TerminalSession::BMAD_DEFAULT_MODULES
  end

  # == mode and initial_prompt columns ==

  test "mode defaults to interactive" do
    session = build(:terminal_session, user: @user)
    assert_equal "interactive", session.mode
  end

  test "mode accepts interactive" do
    session = build(:terminal_session, user: @user, mode: "interactive")
    assert session.valid?
    assert_equal "interactive", session.mode
  end

  test "mode accepts non_interactive with prompt" do
    session = build(:terminal_session, user: @user, mode: "non_interactive", initial_prompt: "Do something")
    assert session.valid?
    assert_equal "non_interactive", session.mode
  end

  test "invalid when non_interactive mode without initial_prompt" do
    session = build(:terminal_session, user: @user, mode: "non_interactive")
    assert_not session.valid?
    assert_includes session.errors[:initial_prompt].join, "can't be blank"
  end

  test "invalid when non_interactive mode with blank initial_prompt" do
    session = build(:terminal_session, user: @user, mode: "non_interactive", initial_prompt: "")
    assert_not session.valid?
    assert_includes session.errors[:initial_prompt].join, "can't be blank"
  end

  test "valid with interactive mode and no initial_prompt" do
    session = build(:terminal_session, user: @user, mode: "interactive")
    assert session.valid?
  end

  test "initial_prompt returns configured value" do
    session = build(:terminal_session, user: @user, mode: "non_interactive", initial_prompt: "Refactor the auth module")
    assert_equal "Refactor the auth module", session.initial_prompt
  end

  # == HABTM associations ==

  test "HABTM tools association works" do
    session = create(:terminal_session, user: @user)
    tool1 = create(:tool, scope: @project)
    tool2 = create(:tool, scope: @project, name: "other-tool")
    session.tools << [ tool1, tool2 ]

    assert_equal 2, session.tools.count
    assert_includes session.tools.pluck(:id), tool1.id
    assert_includes session.tools.pluck(:id), tool2.id
  end

  test "HABTM skills association works" do
    session = create(:terminal_session, user: @user)
    skill = create(:skill, scope: @project)
    session.skills << skill

    assert_equal 1, session.skills.count
    assert_includes session.skills.pluck(:id), skill.id
  end

  test "HABTM mcp_servers association works" do
    session = create(:terminal_session, user: @user)
    mcp = create(:mcp_server, scope: @project)
    session.mcp_servers << mcp

    assert_equal 1, session.mcp_servers.count
    assert_includes session.mcp_servers.pluck(:id), mcp.id
  end

  test "configured_agent belongs_to works" do
    agent = Agent.create!(name: "test_agent", title: "Test Agent", persona: "A test persona", scope: @project)
    session = create(:terminal_session, user: @user, configured_agent: agent)

    assert_equal agent.id, session.configured_agent_id
    assert_equal agent, session.configured_agent
  end

  test "configured_agent_id is nil when not set" do
    session = build(:terminal_session, user: @user)
    assert_nil session.configured_agent_id
  end

  # == available_tools ==

  test "available_tools returns tools from HABTM association" do
    tool1 = create(:tool, scope: @project)
    tool2 = create(:tool, scope: @project, name: "other-tool")

    session = create(:terminal_session, user: @user, project: @project)
    session.tools << [ tool1, tool2 ]

    assert_includes session.available_tools, tool1
    assert_includes session.available_tools, tool2
  end

  test "available_tools falls back to project tools when no HABTM tools" do
    tool = create(:tool, scope: @project)
    session = create(:terminal_session, user: @user, project: @project)

    assert_includes session.available_tools, tool
  end

  test "available_tools returns empty when no project and no tools" do
    session = build(:terminal_session, user: @user, project: nil)
    assert_empty session.available_tools
  end

  # == FK CASCADE / NULLIFY tests ==

  test "deleting a Tool cascade-removes session_tools records" do
    session = create(:terminal_session, user: @user)
    tool = create(:tool, scope: @project)
    session.tools << tool

    assert_equal 1, session.tools.count
    tool.destroy!
    session.reload
    assert_equal 0, session.tools.count
  end

  test "deleting a Skill cascade-removes session_skills records" do
    session = create(:terminal_session, user: @user)
    skill = create(:skill, scope: @project)
    session.skills << skill

    assert_equal 1, session.skills.count
    skill.destroy!
    session.reload
    assert_equal 0, session.skills.count
  end

  test "deleting an MCP server cascade-removes session_mcp_servers records" do
    session = create(:terminal_session, user: @user)
    mcp = create(:mcp_server, scope: @project)
    session.mcp_servers << mcp

    assert_equal 1, session.mcp_servers.count
    mcp.destroy!
    session.reload
    assert_equal 0, session.mcp_servers.count
  end

  test "deleting an Agent nullifies configured_agent_id column" do
    agent = Agent.create!(name: "test_agent", title: "Test Agent", persona: "A test persona", scope: @project)
    session = create(:terminal_session, user: @user, configured_agent: agent)

    assert_equal agent.id, session.configured_agent_id
    agent.destroy!
    session.reload
    assert_nil session.configured_agent_id
  end

  # == backwards compatibility ==

  # == strategy resolution ==

  test "strategy returns AgentAuthStrategy for auth_setup" do
    session = create(:terminal_session, :auth_setup, user: @user)
    strategy = session.strategy

    assert_instance_of ContainerStrategies::AgentAuthStrategy, strategy
    assert_equal @user.id, strategy.input[:user_id]
    assert_equal "claude_code", strategy.input[:agent_type]
    assert_equal session.id, strategy.input[:session_id]
    assert_equal session.route_token, strategy.input[:route_token]
  end

  test "strategy returns AgentSessionStrategy for agent_session" do
    session = create(:terminal_session, :agent_session, user: @user)
    strategy = session.strategy

    assert_instance_of ContainerStrategies::AgentSessionStrategy, strategy
    assert_equal session.id, strategy.input[:session_id]
    assert_nil strategy.input[:credential]
  end

  test "strategy resolves credential for agent_session" do
    credential = AgentCredential.create!(
      user: @user, company: @company, agent_type: "claude_code",
      config_data: { "key" => "val" }
    )
    session = create(:terminal_session, :agent_session, user: @user)
    strategy = session.strategy

    assert_equal credential, strategy.input[:credential]
  end

  test "strategy raises ArgumentError for unsupported session_type" do
    session = build(:terminal_session, user: @user, session_type: "tool_setup", agent_type: nil)

    assert_raises(ArgumentError) { session.strategy }
  end

  # == session-list broadcasts ==

  test "project session updates broadcast only to the project's company" do
    session = create(:terminal_session, user: @user, project: @project)

    ActionCable.server.expects(:broadcast).with("session_list:company:#{@company.id}", anything)
    ActionCable.server.expects(:broadcast).with("session_list:project:#{@project.id}", anything)

    session.send(:broadcast_session_list_update)
  end

  test "project-less session updates broadcast to EVERY company with an active membership" do
    company_b = create(:company)
    create(:company_membership, user: @user, company: company_b)
    revoked_company = create(:company)
    create(:company_membership, :revoked, user: @user, company: revoked_company)

    # company_id nil on purpose: the "every active membership" fan-out is the
    # LEGACY path for rows that never recorded a tenant. New sessions carry
    # company_id and broadcast to that one company only.
    session = build(:terminal_session, :auth_setup, user: @user, project: nil)
    session.company_id = nil
    session.save!(validate: false)

    ActionCable.server.expects(:broadcast).with("session_list:company:#{@company.id}", anything)
    ActionCable.server.expects(:broadcast).with("session_list:company:#{company_b.id}", anything)
    ActionCable.server.expects(:broadcast).with("session_list:company:#{revoked_company.id}", anything).never

    session.send(:broadcast_session_list_update)
  end

  # == backwards compatibility ==

  test "auth_setup sessions work with defaults" do
    session = create(:terminal_session, :auth_setup, user: @user, session_config: {})

    assert session.persisted?
    assert_equal({}, session.session_config)
    assert_equal({}, session.config_files)
    assert_equal({}, session.env_vars)
    assert_nil session.configured_agent_id
    assert_equal 0, session.tools.count
    assert_equal 0, session.skills.count
    assert_equal 0, session.mcp_servers.count
  end
end
