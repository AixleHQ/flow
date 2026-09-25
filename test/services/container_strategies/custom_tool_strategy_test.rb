# frozen_string_literal: true

require "test_helper"

class ContainerStrategies::CustomToolStrategyTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @tool = create(:tool, scope: @project, docker_image: "node:20", command: "node /workspace/main.js")
  end

  teardown do
    cleanup_runtime_overrides
  end

  test "resolve_image returns tool docker_image" do
    strategy = build_strategy
    assert_equal "node:20", strategy.resolve_image
  end

  test "build_working_dir returns /workspace" do
    strategy = build_strategy
    assert_equal "/workspace", strategy.build_working_dir
  end

  test "build_cmd interpolates parameters" do
    @tool.update!(command: "echo {{message}}")
    strategy = build_strategy(parameters: { message: "hello" })
    cmd = strategy.build_cmd
    assert_equal [ "/bin/sh", "-c", "echo hello" ], cmd
  end

  # A Kubernetes pod runs its command the moment it exists, before any file can
  # be written into it, so a tool with files waits behind a gate instead.
  test "build_cmd holds a tool with files behind the start gate" do
    @tool.tool_files.create!(path: "/workspace/script.py", content: "print('hi')")

    shell = build_strategy.build_cmd.last

    assert_match(/until \[ -e #{Regexp.escape(ContainerStrategies::CustomToolStrategy::START_GATE)} \]/, shell)
    assert shell.end_with?("exec /bin/sh -c #{Shellwords.escape(@tool.command)}")
  end

  test "start_container writes every tool file before it opens the gate" do
    @tool.tool_files.create!(path: "/workspace/script.py", content: "print('hi')")
    runtime = stub_container_runtime
    strategy = build_strategy

    strategy.start_container(container_id: "ctr-1")

    order = runtime.fs.keys
    assert_equal "print('hi')", runtime.fs["/workspace/script.py"]
    assert_operator order.index("/workspace/script.py"), :<, order.index(ContainerStrategies::CustomToolStrategy::START_GATE)
  end

  # The command waits for the gate, so a gate that never appears would hold the
  # tool until its whole timeout instead of failing the call.
  test "start_container fails when it cannot open the gate" do
    @tool.tool_files.create!(path: "/workspace/script.py", content: "print('hi')")
    stub_container_runtime.fail_write(ContainerStrategies::CustomToolStrategy::START_GATE)

    error = assert_raises(RuntimeError) { build_strategy.start_container(container_id: "ctr-1") }
    assert_match(/start gate/, error.message)
  end

  test "a tool without files runs its command directly" do
    assert_equal [ "/bin/sh", "-c", @tool.command ], build_strategy.build_cmd
  end

  test "build_env_vars includes parameters as uppercase env" do
    strategy = build_strategy(parameters: { channel: "general", range: "7d" })
    env = strategy.build_env_vars
    assert_includes env, "CHANNEL=general"
    assert_includes env, "RANGE=7d"
  end

  test "build_env_vars includes project env" do
    strategy = build_strategy(project: @project)
    env = strategy.build_env_vars
    assert env.any? { |e| e.start_with?("AIXLE_PROJECT_ID=") }
    assert env.any? { |e| e.start_with?("AIXLE_PROJECT_NAME=") }
  end

  test "build_labels contains tool metadata" do
    strategy = build_strategy
    labels = strategy.build_labels
    assert_equal "tool_execution", labels["aixle.type"]
    assert_equal @tool.id.to_s, labels["aixle.tool_id"]
    assert_equal @tool.name, labels["aixle.tool_name"]
  end

  test "build_host_config applies resource limits" do
    strategy = build_strategy
    hc = strategy.build_host_config
    assert hc["Memory"].present?
    assert hc["CpuQuota"].present?
    refute hc["AutoRemove"]
  end

  test "before_create_container raises without docker_image" do
    @tool.update_column(:docker_image, nil)
    strategy = build_strategy
    error = assert_raises(ArgumentError) { strategy.before_create_container }
    assert_match(/docker_image/, error.message)
  end

  # A repository-bound call carries a reference; the token is minted here, in
  # the activity, narrowed to that repository, and never read from the input.
  test "build_env_vars mints a GITHUB_TOKEN narrowed to the referenced repository" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    integration = create(:integration, company: @company, provider: :github, status: :active, connected_by: @user)
    repo = create(:repository, integration: integration, scope: @project, full_name: "acme/api")
    session.repositories << repo
    tool_result = create(:tool_result, tool: @tool, terminal_session: session)
    fake = FakeGithub::TokenService.new(token: "tok-narrow")
    Github::TokenService.stubs(:new).returns(fake)

    strategy = build_strategy(parameters: { "REPO" => "acme/api",
                                            ContainerStrategies::CustomToolStrategy::REPOSITORY_REFERENCE => repo.id },
                              tool_result_id: tool_result.id)
    env = strategy.build_env_vars

    assert_includes env, "GITHUB_TOKEN=tok-narrow"
    assert_not env.any? { |e| e.start_with?("__AIXLE_REPOSITORY_ID=") }
    assert_equal [ "api" ], fake.calls_to(:generate_installation_token).last[:repositories]
  end

  test "build_env_vars refuses a repository the session does not have" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    tool_result = create(:tool_result, tool: @tool, terminal_session: session)
    stranger = create(:repository, scope: @project)

    strategy = build_strategy(parameters: { ContainerStrategies::CustomToolStrategy::REPOSITORY_REFERENCE => stranger.id },
                              tool_result_id: tool_result.id)

    assert_raises(ArgumentError) { strategy.build_env_vars }
  end

  private

  def build_strategy(parameters: {}, project: nil, tool_result_id: nil)
    ContainerStrategies::CustomToolStrategy.new(
      tool: @tool, parameters: parameters,
      project: project, timeout: 300, tool_result_id: tool_result_id
    )
  end
end
