# frozen_string_literal: true

require "test_helper"

class Tools::CallExecutorTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, company: @user.companies.first, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
  end

  test "app-mode tools execute synchronously through the handler" do
    tool = Tool.shadow_for(Tools::Registry.fetch("list_sub_steps"))

    result = Tools::CallExecutor.execute(tool, {}, @session)

    assert_equal 1, result[:exit_code] # no workflow context — handler error path
    assert_match(/workflow context/i, result[:stderr])
  end

  test "container tools create a processing ToolResult and return its execution_id as stdout" do
    tool = create(:tool, scope: @project, name: "my_linter", docker_image: "linter:1.0")
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

  # == the legacy GitHub repository binding ==
  #
  # The expansion used to fire on ANY argument spelled `repository_id`, which
  # made an argument NAME imply GitHub authentication. Now it is declared:
  # container tools (the real consumers — user-authored shell tools whose scripts
  # read $REPO and $GITHUB_TOKEN) keep it unconditionally, and a code-defined app
  # tool must opt in.

  test "a container tool still gets REPO, GITHUB_TOKEN and BRANCH from the attached repository" do
    repo, fake_github = attached_github_repository
    tool = create(:tool, scope: @project, name: "my_linter", docker_image: "linter:1.0")
    captured = nil
    # The payload is the SECOND positional argument to start_workflow; the
    # parameters inside it are what the container's script sees as env.
    TemporalService.stubs(:start_workflow).with { |*args, **| captured = args[1]; true }
                   .returns({ ok: true, workflow_id: "wf", run_id: "r" })

    Tools::CallExecutor.execute(tool, { "repository_id" => repo.id }, @session)

    params = captured[:parameters]
    assert_equal repo.full_name, params["REPO"]
    assert_equal "tok-123", params["GITHUB_TOKEN"]
    assert_equal repo.source_branch, params["BRANCH"]
    assert_nil params["repository_id"]
    assert fake_github.called?(:generate_installation_token)
  end

  test "an app tool that declares the legacy binding gets the expansion" do
    repo, = attached_github_repository
    tool = Tool.shadow_for(Tools::Registry.fetch("list_sub_steps"))
    tool.stubs(:definition).returns(legacy_bound_definition)
    captured = capture_app_params

    Tools::CallExecutor.execute(tool, { "repository_id" => repo.id }, @session)

    assert_equal repo.full_name, captured[:params]["REPO"]
    assert_equal "tok-123", captured[:params]["GITHUB_TOKEN"]
    assert_nil captured[:params]["repository_id"]
  end

  # The case the change exists for: a native provider handler keeps the argument
  # it declared, and resolves its own credentials in Rails. Before this, an Azure
  # tool would have had `repository_id` deleted and been handed a GitHub token
  # for a repository the executor had already refused.
  test "an app tool that declares no binding receives its own arguments untouched" do
    repo, = attached_github_repository
    tool = Tool.shadow_for(Tools::Registry.fetch("list_sub_steps"))
    captured = capture_app_params

    Tools::CallExecutor.execute(tool, { "repository_id" => repo.id }, @session)

    assert_equal repo.id, captured[:params]["repository_id"]
    assert_nil captured[:params]["REPO"]
    assert_nil captured[:params]["GITHUB_TOKEN"]
  end

  test "a public repository_id raises instead of minting a token it has no installation for" do
    repo = create(:repository, :public_source, scope: @project, full_name: "rails/rails",
                  clone_url: "https://github.com/rails/rails.git")
    @session.repositories << repo
    tool = Tool.shadow_for(Tools::Registry.fetch("list_sub_steps"))
    tool.stubs(:definition).returns(legacy_bound_definition)

    error = assert_raises(RuntimeError) do
      Tools::CallExecutor.execute(tool, { "repository_id" => repo.id }, @session)
    end
    assert_match(/public read-only source/, error.message)
  end

  test "unattached repository_id raises for a legacy-bound tool" do
    tool = Tool.shadow_for(Tools::Registry.fetch("list_sub_steps"))
    tool.stubs(:definition).returns(legacy_bound_definition)

    assert_raises(RuntimeError) do
      Tools::CallExecutor.execute(tool, { "repository_id" => 999_999 }, @session)
    end
  end

  private

  def attached_github_repository
    integration = create(:integration, company: @user.companies.first, provider: :github,
                         status: :active, connected_by: @user)
    repo = create(:repository, integration: integration, scope: @project)
    @session.repositories << repo
    fake_github = FakeGithub::TokenService.new(token: "tok-123")
    Github::TokenService.stubs(:new).returns(fake_github)
    [ repo, fake_github ]
  end

  # A real Definition carrying the opt-in, so the executor's dispatch is
  # exercised rather than a stubbed predicate.
  def legacy_bound_definition
    base = Tools::Registry.fetch("list_sub_steps")
    Tools::Definition.new(
      **Tools::Definition::ATTRS.to_h { |a| [ a, base.public_send(a) ] },
      repository_binding: :legacy_github
    )
  end

  def capture_app_params
    captured = {}
    InternalToolExecutor.stubs(:execute).with { |_t, params, _s, **| captured[:params] = params; true }
                        .returns({ exit_code: 0, stdout: "ok", stderr: "" })
    captured
  end
end
