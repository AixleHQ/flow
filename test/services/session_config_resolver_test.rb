# frozen_string_literal: true

require "test_helper"

class SessionConfigResolverTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  # --- Session Type Detection ---

  test "standalone session type when no step_run" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    result = SessionConfigResolver.resolve(session)

    assert_equal :standalone, result[:session_type]
  end

  test "workflow session type when step_run present without board_task" do
    session = build_workflow_session

    result = SessionConfigResolver.resolve(session)

    assert_equal :workflow, result[:session_type]
  end

  test "board_triggered session type when step_run and board_task present" do
    session = build_board_triggered_session

    result = SessionConfigResolver.resolve(session)

    assert_equal :board_triggered, result[:session_type]
  end

  # --- Return Structure ---

  test "result contains all required keys" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    result = SessionConfigResolver.resolve(session)

    expected_keys = %i[session_type agent_runtime configured_agent_id tool_ids skill_ids
                       mcp_server_ids repository_ids input_asset_ids mode]
    expected_keys.each do |key|
      assert result.key?(key), "Missing key: #{key}"
    end
  end

  # --- Standalone Pass-through ---

  test "standalone session returns agent_type as agent_runtime" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      agent_type: "gemini_cli")

    result = SessionConfigResolver.resolve(session)

    assert_equal "gemini_cli", result[:agent_runtime]
  end

  test "standalone session returns configured_agent_id" do
    agent = Agent.create!(name: "test_agent", title: "Test Agent", persona: "A persona", scope: @project)
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      configured_agent: agent)

    result = SessionConfigResolver.resolve(session)

    assert_equal agent.id, result[:configured_agent_id]
  end

  test "standalone session returns mode" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "non_interactive", initial_prompt: "test")

    result = SessionConfigResolver.resolve(session)

    assert_equal "non_interactive", result[:mode]
  end

  test "standalone session returns tool_ids from association" do
    tool = create(:tool, scope: @project)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << tool

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:tool_ids], tool.id
  end

  test "standalone session returns skill_ids from association" do
    skill = create(:skill, scope: @project)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.skills << skill

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:skill_ids], skill.id
  end

  # --- Workflow Resolution (stub level for 29.1) ---

  test "workflow session returns step tool_ids" do
    session = build_workflow_session(step_tool_ids: [ 10, 20 ])

    result = SessionConfigResolver.resolve(session)

    assert_equal [ 10, 20 ], result[:tool_ids]
  end

  test "workflow session returns agent_runtime from workflow_run" do
    session = build_workflow_session(agent_runtime: "codex")

    result = SessionConfigResolver.resolve(session)

    assert_equal "codex", result[:agent_runtime]
  end

  test "workflow session falls back to claude_code when no agent_runtime" do
    session = build_workflow_session(agent_runtime: nil)

    result = SessionConfigResolver.resolve(session)

    assert_equal "claude_code", result[:agent_runtime]
  end

  test "workflow session returns step agent_id as configured_agent_id" do
    agent = Agent.create!(name: "test_agent", title: "Test Agent", persona: "A persona", scope: @project)
    session = build_workflow_session(step_agent: agent)

    result = SessionConfigResolver.resolve(session)

    assert_equal agent.id, result[:configured_agent_id]
  end

  test "workflow session resolves mode from workflow_run" do
    session = build_workflow_session(run_mode: "non_interactive")

    result = SessionConfigResolver.resolve(session)

    assert_equal "non_interactive", result[:mode]
  end

  test "workflow session resolves mode interactive by default" do
    session = build_workflow_session(run_mode: "interactive")

    result = SessionConfigResolver.resolve(session)

    assert_equal "interactive", result[:mode]
  end

  test "workflow session resolves repositories when mount_repositories true" do
    integration = create(:integration, :github, company: @company, connected_by: @user)
    repo = create(:repository, scope: @project, integration: integration)
    session = build_workflow_session(mount_repositories: true, run_repository_ids: [ repo.id ])

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:repository_ids], repo.id
  end

  test "board_triggered session falls back to project repositories when run repositories are empty" do
    integration = create(:integration, :github, company: @company, connected_by: @user)
    repo = create(:repository, scope: @project, integration: integration)
    session = build_board_triggered_session(
      mount_repositories: true,
      run_repository_ids: [],
      workflow_config: { "inherit_all_project_resources" => true }
    )

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:repository_ids], repo.id
  end

  test "board_triggered session fallback includes company repositories visible to project" do
    integration = create(:integration, :github, company: @company, connected_by: @user)
    repo = create(:repository, scope: @project, integration: integration)
    session = build_board_triggered_session(
      mount_repositories: true,
      run_repository_ids: [],
      workflow_config: { "inherit_all_project_resources" => true }
    )

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:repository_ids], repo.id
  end

  test "board_triggered session does not fallback to project repositories when inherit_all_project_resources false" do
    integration = create(:integration, :github, company: @company, connected_by: @user)
    create(:repository, scope: @project, integration: integration)
    session = build_board_triggered_session(
      mount_repositories: true,
      run_repository_ids: [],
      workflow_config: { "inherit_all_project_resources" => false }
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal [], result[:repository_ids]
  end

  test "non-board workflow session does not fallback to project repositories when run repositories are empty" do
    integration = create(:integration, :github, company: @company, connected_by: @user)
    create(:repository, scope: @project, integration: integration)
    session = build_workflow_session(mount_repositories: true, run_repository_ids: [])

    result = SessionConfigResolver.resolve(session)

    assert_equal [], result[:repository_ids]
  end

  test "workflow session returns empty repositories when mount_repositories false" do
    session = build_workflow_session(mount_repositories: false)

    result = SessionConfigResolver.resolve(session)

    assert_equal [], result[:repository_ids]
  end

  test "board_triggered session does not fallback when mount_repositories false" do
    integration = create(:integration, :github, company: @company, connected_by: @user)
    create(:repository, scope: @project, integration: integration)
    session = build_board_triggered_session(mount_repositories: false, run_repository_ids: [])

    result = SessionConfigResolver.resolve(session)

    assert_equal [], result[:repository_ids]
  end

  test "workflow session returns input_asset_ids from workflow_run" do
    session = build_workflow_session(run_input_asset_ids: [ 100, 101 ])

    result = SessionConfigResolver.resolve(session)

    assert_equal [ 100, 101 ], result[:input_asset_ids]
  end

  # === Story 29.2: Additive Resource Resolution ===

  test "workflow session merges workflow base + step tools" do
    session = build_workflow_session(
      workflow_config: { "base_tool_ids" => [ 1, 2 ] },
      step_tool_ids: [ 2, 3 ]
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal [ 1, 2, 3 ], result[:tool_ids].sort
  end

  test "workflow session merges workflow base + step skills" do
    session = build_workflow_session(
      workflow_config: { "base_skill_ids" => [ 10 ] },
      step_skill_ids: [ 11 ]
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal [ 10, 11 ], result[:skill_ids].sort
  end

  test "workflow session returns workflow base mcp when step has none" do
    session = build_workflow_session(
      workflow_config: { "base_mcp_server_ids" => [ 20 ] },
      step_mcp_server_ids: []
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal [ 20 ], result[:mcp_server_ids]
  end

  test "workflow session returns step tools when no workflow base" do
    session = build_workflow_session(step_tool_ids: [ 7 ])

    result = SessionConfigResolver.resolve(session)

    assert_equal [ 7 ], result[:tool_ids]
  end

  # === Story 29.3: Workflow inherit_all_project_resources ===

  test "inherit_all adds project tools to resolution" do
    project_tool = create(:tool, scope: @project)
    session = build_workflow_session(
      workflow_config: { "inherit_all_project_resources" => true, "base_tool_ids" => [] },
      step_tool_ids: []
    )

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:tool_ids], project_tool.id
  end

  test "inherit_all false excludes project tools" do
    create(:tool, scope: @project)
    session = build_workflow_session(
      workflow_config: { "inherit_all_project_resources" => false },
      step_tool_ids: [ 99 ]
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal [ 99 ], result[:tool_ids]
  end

  test "inherit_all adds project skills" do
    project_skill = create(:skill, scope: @project)
    session = build_workflow_session(
      workflow_config: { "inherit_all_project_resources" => true }
    )

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:skill_ids], project_skill.id
  end

  test "inherit_all adds project mcp_servers" do
    project_mcp = create(:mcp_server, scope: @project)
    session = build_workflow_session(
      workflow_config: { "inherit_all_project_resources" => true }
    )

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:mcp_server_ids], project_mcp.id
  end

  test "inherit_all default is false when missing from config" do
    workflow = create(:workflow, :with_project_scope, config: {})

    # The documented contract is exactly `false`, not merely falsy (nil).
    assert_equal false, workflow.inherit_all_project_resources # rubocop:disable Minitest/RefuteFalse
  end

  test "inherit_all with step tools are additive" do
    project_tool = create(:tool, scope: @project)
    session = build_workflow_session(
      workflow_config: { "inherit_all_project_resources" => true },
      step_tool_ids: [ 999 ]
    )

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:tool_ids], project_tool.id
    assert_includes result[:tool_ids], 999
  end

  # === Story 29.5: Step required_agent_runtime ===

  test "step required_agent_runtime overrides everything" do
    create(:agent_credential, user: @user, agent_type: "gemini_cli")
    session = build_workflow_session(
      agent_runtime: "codex",
      step_required_agent_runtime: "claude_code"
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal "claude_code", result[:agent_runtime]
  end

  test "workflow_run agent_runtime used when step has no requirement" do
    session = build_workflow_session(
      agent_runtime: "gemini_cli",
      step_required_agent_runtime: nil
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal "gemini_cli", result[:agent_runtime]
  end

  test "user latest credential used when no step or run runtime" do
    create(:agent_credential, user: @user, agent_type: "codex")
    session = build_workflow_session(
      agent_runtime: nil,
      step_required_agent_runtime: nil
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal "codex", result[:agent_runtime]
  end

  test "falls back to claude_code when no credentials at all" do
    session = build_workflow_session(
      agent_runtime: nil,
      step_required_agent_runtime: nil
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal "claude_code", result[:agent_runtime]
  end

  # === Story 29.4: Input Assets Resolution with Board Task Assets ===

  test "workflow session merges base + run assets for board_triggered" do
    session = build_board_triggered_session(
      workflow_config: { "base_asset_ids" => [ 100 ] },
      run_input_asset_ids: [ 101 ]
    )

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:input_asset_ids], 100
    assert_includes result[:input_asset_ids], 101
    assert_equal :board_triggered, result[:session_type]
  end

  test "workflow session without board_task returns base + run assets" do
    session = build_workflow_session(
      workflow_config: { "base_asset_ids" => [ 100 ] },
      run_input_asset_ids: [ 101 ]
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal [ 100, 101 ], result[:input_asset_ids]
  end

  test "workflow session merges base + step + run assets" do
    session = build_workflow_session(
      workflow_config: { "base_asset_ids" => [ 100 ] },
      step_asset_ids: [ 200 ],
      run_input_asset_ids: [ 101 ]
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal [ 100, 200, 101 ], result[:input_asset_ids]
  end

  test "workflow session deduplicates assets shared across base and step" do
    session = build_workflow_session(
      workflow_config: { "base_asset_ids" => [ 100 ] },
      step_asset_ids: [ 100, 200 ]
    )

    result = SessionConfigResolver.resolve(session)

    assert_equal [ 100, 200 ], result[:input_asset_ids]
  end

  # === Story 29.7: Config Resolution Traceability ===

  test "resolve_with_breakdown returns agent_runtime_source step_required" do
    session = build_workflow_session(
      step_required_agent_runtime: "claude_code",
      agent_runtime: "gemini_cli"
    )

    result = SessionConfigResolver.resolve_with_breakdown(session)

    assert_equal "step_required", result[:agent_runtime_source]
  end

  test "resolve_with_breakdown returns agent_runtime_source run_override" do
    session = build_workflow_session(agent_runtime: "codex")

    result = SessionConfigResolver.resolve_with_breakdown(session)

    assert_equal "run_override", result[:agent_runtime_source]
  end

  test "resolve_with_breakdown returns agent_runtime_source fallback" do
    session = build_workflow_session(agent_runtime: nil)

    result = SessionConfigResolver.resolve_with_breakdown(session)

    assert_equal "fallback", result[:agent_runtime_source]
  end

  test "resolve_with_breakdown returns tool breakdown for workflow" do
    session = build_workflow_session(
      workflow_config: { "base_tool_ids" => [ 1 ] },
      step_tool_ids: [ 2, 3 ]
    )

    result = SessionConfigResolver.resolve_with_breakdown(session)

    assert_equal [ 1 ], result[:tools][:from_workflow_base]
    assert_equal [ 2, 3 ], result[:tools][:from_step]
    assert_equal [ 1, 2, 3 ], result[:tools][:resolved].sort
  end

  test "resolve_with_breakdown returns input_asset breakdown" do
    session = build_workflow_session(
      workflow_config: { "base_asset_ids" => [ 100 ] },
      step_asset_ids: [ 200 ],
      run_input_asset_ids: [ 101 ]
    )

    result = SessionConfigResolver.resolve_with_breakdown(session)

    assert_equal [ 100 ], result[:input_assets][:from_workflow_base]
    assert_equal [ 200 ], result[:input_assets][:from_step]
    assert_equal [ 101 ], result[:input_assets][:from_run_user]
    assert_equal [ 100, 200, 101 ], result[:input_assets][:resolved]
  end

  test "resolve_with_breakdown returns repository project fallback for board_triggered sessions" do
    integration = create(:integration, :github, company: @company, connected_by: @user)
    repo = create(:repository, scope: @project, integration: integration)
    session = build_board_triggered_session(
      mount_repositories: true,
      run_repository_ids: [],
      workflow_config: { "inherit_all_project_resources" => true }
    )

    result = SessionConfigResolver.resolve_with_breakdown(session)

    assert_equal [], result[:repositories][:from_run]
    assert_includes result[:repositories][:from_project_fallback], repo.id
    assert_includes result[:repositories][:resolved], repo.id
  end

  test "resolve_with_breakdown repository fallback includes company repositories visible to project" do
    integration = create(:integration, :github, company: @company, connected_by: @user)
    repo = create(:repository, scope: @project, integration: integration)
    session = build_board_triggered_session(
      mount_repositories: true,
      run_repository_ids: [],
      workflow_config: { "inherit_all_project_resources" => true }
    )

    result = SessionConfigResolver.resolve_with_breakdown(session)

    assert_equal [], result[:repositories][:from_run]
    assert_includes result[:repositories][:from_project_fallback], repo.id
    assert_includes result[:repositories][:resolved], repo.id
  end

  test "resolve_with_breakdown omits project repository fallback when inherit_all_project_resources false" do
    integration = create(:integration, :github, company: @company, connected_by: @user)
    create(:repository, scope: @project, integration: integration)
    session = build_board_triggered_session(
      mount_repositories: true,
      run_repository_ids: [],
      workflow_config: { "inherit_all_project_resources" => false }
    )

    result = SessionConfigResolver.resolve_with_breakdown(session)

    assert_equal [], result[:repositories][:from_run]
    assert_equal [], result[:repositories][:from_project_fallback]
    assert_equal [], result[:repositories][:resolved]
  end

  test "resolve_with_breakdown returns empty repositories when mount_repositories false even for board_triggered" do
    integration = create(:integration, :github, company: @company, connected_by: @user)
    create(:repository, scope: @project, integration: integration)
    session = build_board_triggered_session(mount_repositories: false, run_repository_ids: [])

    result = SessionConfigResolver.resolve_with_breakdown(session)

    assert_equal [], result[:repositories][:resolved]
    refute result[:repositories].key?(:from_project_fallback)
    refute result[:repositories].key?(:from_run)
  end

  test "resolve_with_breakdown returns session_direct for standalone" do
    tool = create(:tool, scope: @project)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.tools << tool

    result = SessionConfigResolver.resolve_with_breakdown(session)

    assert_equal "session_direct", result[:agent_runtime_source]
    assert_includes result[:tools][:from_session_direct], tool.id
  end

  test "context_result includes config_resolution in to_json_hash" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "non_interactive", initial_prompt: "work")

    result = SessionContextConstructor.build_result(session)
    json = result.to_json_hash

    assert json.key?(:config_resolution)
    assert_equal "standalone", json[:config_resolution][:session_type].to_s
  end

  test "standalone session input_assets are pass-through" do
    asset = create(:asset, scope: @project, created_by: @user)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    session.input_assets << asset

    result = SessionConfigResolver.resolve(session)

    assert_includes result[:input_asset_ids], asset.id
  end

  # --- BMAD Enabled Resolution ---

  test "resolve_bmad_enabled returns true for standalone session with bmad_enabled" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
                     session_config: { "bmad_enabled" => true })

    result = SessionConfigResolver.resolve(session)

    assert result[:bmad_enabled]
  end

  test "resolve_bmad_enabled returns false for standalone session without bmad_enabled" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    result = SessionConfigResolver.resolve(session)

    refute result[:bmad_enabled]
  end

  test "resolve_bmad_enabled returns true for workflow step with bmad_enabled" do
    session = build_workflow_session(step_bmad_enabled: true)

    result = SessionConfigResolver.resolve(session)

    assert result[:bmad_enabled]
  end

  test "resolve_bmad_enabled returns false for workflow step without bmad_enabled" do
    session = build_workflow_session

    result = SessionConfigResolver.resolve(session)

    refute result[:bmad_enabled]
  end

  test "resolve_bmad_enabled included in resolve_with_breakdown" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
                     session_config: { "bmad_enabled" => true })

    breakdown = SessionConfigResolver.resolve_with_breakdown(session)

    assert breakdown[:bmad_enabled]
  end

  private

  def build_workflow_session(step_tool_ids: [], step_skill_ids: [], step_mcp_server_ids: [],
                             step_asset_ids: [],
                             agent_runtime: "claude_code", step_agent: nil,
                             run_mode: "interactive", mount_repositories: true,
                             run_repository_ids: [], run_input_asset_ids: [],
                             board_task: nil, workflow_config: {},
                             step_required_agent_runtime: nil,
                             step_bmad_enabled: false)
    workflow = create(:workflow, :with_project_scope, config: workflow_config)
    step = create(:step, workflow: workflow, tool_ids: step_tool_ids, skill_ids: step_skill_ids,
      mcp_server_ids: step_mcp_server_ids, asset_ids: step_asset_ids, agent: step_agent,
      mount_repositories: mount_repositories,
      required_agent_runtime: step_required_agent_runtime, bmad_enabled: step_bmad_enabled)
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user,
      agent_runtime: agent_runtime, mode: run_mode, repository_ids: run_repository_ids,
      input_asset_ids: run_input_asset_ids, board_task: board_task)

    session = create(:terminal_session, user: @user, project: @project,
      session_type: "workflow_step", agent_type: agent_runtime || "claude_code")

    step_run = create(:step_run, workflow_run: workflow_run, step: step, terminal_session: session)
    session.reload

    session
  end

  def build_board_triggered_session(**opts)
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    task = create(:board_task, board: board, board_column: column)

    build_workflow_session(**opts.merge(board_task: task))
  end
end
