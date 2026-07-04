# frozen_string_literal: true

require "test_helper"

class Tools::CallExecutorTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, company: @user.company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
  end

  test "app-mode tools execute synchronously through the handler" do
    tool = Tool.shadow_for(Tools::Registry.fetch("list_sub_steps"))

    result = Tools::CallExecutor.execute(tool, {}, @session)

    assert_equal 1, result[:exit_code] # no workflow context — handler error path
    assert_match(/workflow context/i, result[:stderr])
  end

  test "container tools create a processing ToolResult and return its execution_id as stdout" do
    tool = create(:tool, scope: @user.company, name: "my_linter", docker_image: "linter:1.0")
    TemporalService.stubs(:start_workflow).returns({ ok: true, workflow_id: "wf", run_id: "r" })

    result = Tools::CallExecutor.execute(tool, { "path" => "/workspace" }, @session)

    assert_equal 0, result[:exit_code]
    tr = ToolResult.find_by(execution_id: result[:stdout])
    assert_equal "processing", tr.state
    assert_equal tool, tr.tool
    assert_equal @session, tr.terminal_session
  end

  test "response_content shapes errors with the exit code header" do
    content = Tools::CallExecutor.response_content(exit_code: 2, stdout: "out", stderr: "boom")

    assert_equal [ "Error (exit 2):", "boom", "out" ], content.map { |c| c[:text] }
    assert_equal [ { type: "text", text: "(no output)" } ],
                 Tools::CallExecutor.response_content(exit_code: 0, stdout: "", stderr: "")
  end

  test "repository_id resolves REPO, GITHUB_TOKEN and BRANCH from the attached repository" do
    integration = create(:integration, company: @user.company, provider: :github,
                         status: :active, connected_by: @user)
    repo = create(:repository, integration: integration, scope: @project)
    @session.repositories << repo
    Github::TokenService.stubs(:new).returns(stub(generate_installation_token: "tok-123"))
    tool = Tool.shadow_for(Tools::Registry.fetch("list_sub_steps"))
    captured = nil
    InternalToolExecutor.stubs(:execute).with { |_t, params, _s, **| captured = params; true }
                        .returns({ exit_code: 0, stdout: "ok", stderr: "" })

    Tools::CallExecutor.execute(tool, { "repository_id" => repo.id }, @session)

    assert_equal repo.full_name, captured["REPO"]
    assert_equal "tok-123", captured["GITHUB_TOKEN"]
    assert_equal repo.source_branch, captured["BRANCH"]
    assert_nil captured["repository_id"]
  end

  test "unattached repository_id raises" do
    tool = Tool.shadow_for(Tools::Registry.fetch("list_sub_steps"))

    assert_raises(RuntimeError) do
      Tools::CallExecutor.execute(tool, { "repository_id" => 999_999 }, @session)
    end
  end
end
