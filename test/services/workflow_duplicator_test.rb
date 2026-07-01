# frozen_string_literal: true

require "test_helper"

class WorkflowDuplicatorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    # Real company-scoped dependency resources referenced by the source workflow.
    @agent = create(:agent, scope: @company, name: "researcher", title: "Researcher",
                            persona: "You research things.")
    @skill = create(:skill, scope: @company)
    @mcp = create(:mcp_server, scope: @company, name: "context7")
    @tool = create(:tool, :with_company_scope, name: "my_tool")

    @source = create(:workflow, scope: @company, name: "Source WF",
                                config: {
                                  "base_tool_ids" => [ @tool.id ],
                                  "base_skill_ids" => [ @skill.id ],
                                  "base_mcp_server_ids" => [ @mcp.id ]
                                })
    @step1 = create(:step, workflow: @source, position: 1, name: "First",
                           agent_id: @agent.id,
                           tool_ids: [ @tool.id ], skill_ids: [ @skill.id ],
                           mcp_server_ids: [ @mcp.id ], asset_ids: [ 42, 43 ])
    @step2 = create(:step, workflow: @source, position: 2, name: "Second",
                           depends_on_step_ids: [ @step1.id ],
                           preferred_model: "claude-sonnet-4",
                           bmad_enabled: true,
                           required_agent_runtime: "claude_code")
    create(:sub_step, step: @step1, name: "Sub 1")
  end

  test "duplicates workflow with steps sub_steps and remapped step-graph dependencies" do
    copy = WorkflowDuplicator.new(@source, target_scope: @project).duplicate!

    assert_equal "Project", copy.scope_type
    assert_equal @project.id, copy.scope_id
    assert_equal 2, copy.steps.not_deleted.count

    copied_steps = copy.steps.not_deleted.order(:position).to_a
    assert_equal [ "First", "Second" ], copied_steps.map(&:name)
    assert_equal copied_steps[0].id, copied_steps[1].depends_on_step_ids.first
    assert_equal "claude-sonnet-4", copied_steps[1].preferred_model
    assert copied_steps[1].bmad_enabled
    assert_equal "claude_code", copied_steps[1].required_agent_runtime
    assert_equal 1, copied_steps[0].sub_steps.active.count
    # assets are intentionally NOT copied — asset_ids pass through unchanged (D5)
    assert_equal [ 42, 43 ], copied_steps[0].asset_ids
  end

  test "copies referenced Company agent into the target project and remaps agent_id" do
    copy = WorkflowDuplicator.new(@source, target_scope: @project).duplicate!
    new_step = copy.steps.not_deleted.order(:position).first

    refute_equal @agent.id, new_step.agent_id
    new_agent = Agent.find(new_step.agent_id)
    assert_equal "Project", new_agent.scope_type
    assert_equal @project.id, new_agent.scope_id
    assert_equal "researcher", new_agent.name
    assert_equal "Researcher", new_agent.title
    assert_equal "You research things.", new_agent.persona
  end

  test "copies referenced Company skill mcp tool and remaps step arrays + config" do
    copy = WorkflowDuplicator.new(@source, target_scope: @project).duplicate!
    new_step = copy.steps.not_deleted.order(:position).first

    # Arrays are remapped to new, project-local IDs (and are never nil).
    refute_equal [ @skill.id ], new_step.skill_ids
    refute_equal [ @mcp.id ], new_step.mcp_server_ids
    refute_equal [ @tool.id ], new_step.tool_ids
    assert_equal 1, new_step.skill_ids.size
    assert_equal 1, new_step.mcp_server_ids.size
    assert_equal 1, new_step.tool_ids.size

    assert_equal "Project", Skill.find(new_step.skill_ids.first).scope_type
    assert_equal @project.id, Skill.find(new_step.skill_ids.first).scope_id
    assert_equal @project.id, MCPServer.find(new_step.mcp_server_ids.first).scope_id
    assert_equal @project.id, Tool.find(new_step.tool_ids.first).scope_id

    # config.base_*_ids are remapped and never nil.
    assert_equal new_step.tool_ids, copy.config["base_tool_ids"]
    assert_equal new_step.skill_ids, copy.config["base_skill_ids"]
    assert_equal new_step.mcp_server_ids, copy.config["base_mcp_server_ids"]
    [ "base_tool_ids", "base_skill_ids", "base_mcp_server_ids" ].each do |key|
      assert_not_nil copy.config[key]
    end
  end

  test "idempotent reuse: two steps sharing an agent produce one project-local agent" do
    create(:step, workflow: @source, position: 3, name: "Third", agent_id: @agent.id)

    assert_difference -> { @project.agents.count }, 1 do
      WorkflowDuplicator.new(@source, target_scope: @project).duplicate!
    end
  end

  test "idempotent reuse: running the duplicator twice does not create duplicate resources" do
    WorkflowDuplicator.new(@source, target_scope: @project).duplicate!

    assert_no_difference [ -> { @project.agents.count }, -> { Skill.for_project(@project).count },
                           -> { MCPServer.for_project(@project).count }, -> { Tool.for_project(@project).count } ] do
      WorkflowDuplicator.new(@source, target_scope: @project).duplicate!
    end
  end

  test "pass-through: System agent, platform tool, internal MCP keep original IDs and create no rows" do
    sys_agent = create(:agent, :system, name: "system_agent")
    sys_tool = create(:tool, :system, name: "system_tool")
    internal_mcp = create(:mcp_server, :internal, name: "aixle-internal")

    @step1.update!(agent_id: sys_agent.id, tool_ids: [ sys_tool.id ], mcp_server_ids: [ internal_mcp.id ])

    copy = WorkflowDuplicator.new(@source, target_scope: @project).duplicate!
    new_step = copy.steps.not_deleted.order(:position).first

    assert_equal sys_agent.id, new_step.agent_id
    assert_equal [ sys_tool.id ], new_step.tool_ids
    assert_equal [ internal_mcp.id ], new_step.mcp_server_ids
    refute Agent.for_project(@project).exists?
  end

  test "managed MCP that stays visible in target is kept by ID and not copied" do
    integration = create(:integration, :coder, :active, company: @company, project: nil, connected_by: @user)
    managed = create(:mcp_server, kind: :managed, scope: @company, integration: integration,
                                  name: "coder-mcp", url: "https://coder.example.com")
    @step1.update!(mcp_server_ids: [ managed.id ])

    copy = WorkflowDuplicator.new(@source, target_scope: @project).duplicate!
    new_step = copy.steps.not_deleted.order(:position).first

    assert_equal [ managed.id ], new_step.mcp_server_ids
    assert_equal 0, MCPServer.managed_servers.for_integration(integration).where(scope: @project).count
  end

  test "managed MCP not visible in target has its reference dropped and is summarized" do
    other_project = create(:project, company: @company, owner: @user)
    integration = create(:integration, :coder, :active, company: @company, project: other_project, connected_by: @user)
    managed = create(:mcp_server, kind: :managed, scope: other_project, integration: integration,
                                  name: "other-coder", url: "https://coder.example.com")
    @step1.update!(mcp_server_ids: [ managed.id ])

    duplicator = WorkflowDuplicator.new(@source, target_scope: @project)
    copy = duplicator.duplicate!
    new_step = copy.steps.not_deleted.order(:position).first

    assert_equal [], new_step.mcp_server_ids
    assert(duplicator.summary[:needs_setup].any? { |m| m.include?("Managed MCP") })
  end

  test "copies binary tool file via Shrine file_data, and text tool file via content" do
    binary_tool = create(:tool, :with_company_scope, name: "binary_tool")
    binary_tool.tool_files.create!(path: "/workspace/bin/tool", file: StringIO.new("\x00\x01BINARY\x02"))
    binary_tool.tool_files.create!(path: "/workspace/readme.txt", content: "hello text")
    @step1.update!(tool_ids: [ binary_tool.id ])

    copy = WorkflowDuplicator.new(@source, target_scope: @project).duplicate!
    new_tool = Tool.find(copy.steps.not_deleted.order(:position).first.tool_ids.first)

    binary_file = new_tool.tool_files.find { |tf| tf.path == "/workspace/bin/tool" }
    text_file = new_tool.tool_files.find { |tf| tf.path == "/workspace/readme.txt" }

    assert binary_file.binary?, "expected copied binary tool file to have a Shrine file attachment"
    assert_equal "\x00\x01BINARY\x02".b, binary_file.file.download.read.b
    assert_equal "hello text", text_file.content
  end

  test "copies requires_integration tool as gated: excluded from pickers until integration active" do
    gated_tool = create(:tool, :with_company_scope, name: "slack_tool", requires_integration: "slack")
    @step1.update!(tool_ids: [ gated_tool.id ])

    duplicator = WorkflowDuplicator.new(@source, target_scope: @project)
    copy = duplicator.duplicate!
    new_tool = Tool.find(copy.steps.not_deleted.order(:position).first.tool_ids.first)

    assert_equal "slack", new_tool.requires_integration
    refute Tool.visible_for_project(@project).exists?(id: new_tool.id)

    create(:integration, provider: :slack, status: :active, company: @company, project: nil, connected_by: @user)
    assert Tool.visible_for_project(@project).exists?(id: new_tool.id)
    assert(duplicator.summary[:needs_setup].any? { |m| m.include?("integration") })
  end

  test "secrets boundary: MCP env/headers copied VERBATIM and no ConfigItem rows created" do
    server = create(:mcp_server, scope: @company, name: "secured",
                                 headers: { "Authorization" => "Bearer config_item:API_KEY" },
                                 env: { "BASE_URL" => "https://api.example.com", "MODEL" => "gpt-4o" })
    @step1.update!(mcp_server_ids: [ server.id ])

    duplicator = WorkflowDuplicator.new(@source, target_scope: @project)
    copy = nil
    assert_no_difference -> { ConfigItem.count } do
      copy = duplicator.duplicate!
    end

    new_mcp = MCPServer.find(copy.steps.not_deleted.order(:position).first.mcp_server_ids.first)
    # config_item:NAME reference preserved verbatim
    assert_equal "Bearer config_item:API_KEY", new_mcp.headers["Authorization"]
    # non-config_item literals preserved unchanged (NOT scrubbed)
    assert_equal "https://api.example.com", new_mcp.env["BASE_URL"]
    assert_equal "gpt-4o", new_mcp.env["MODEL"]

    # summary enumerates the config item the workflow relies on
    assert(duplicator.summary[:needs_setup].any? { |m| m.include?("API_KEY") })
  end

  test "generates unique name when duplicate exists" do
    create(:workflow, scope: @project, name: "Source WF")

    copy = WorkflowDuplicator.new(@source, target_scope: @project).duplicate!

    assert_equal "Source WF (1)", copy.name
  end

  test "uses explicit name when provided" do
    copy = WorkflowDuplicator.new(@source, target_scope: @project, name: "Custom Name").duplicate!

    assert_equal "Custom Name", copy.name
  end

  test "generates unique name when explicit name collides" do
    create(:workflow, scope: @project, name: "Custom Name")

    copy = WorkflowDuplicator.new(@source, target_scope: @project, name: "Custom Name").duplicate!

    assert_equal "Custom Name (1)", copy.name
  end
end
