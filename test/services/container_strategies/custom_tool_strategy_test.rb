# frozen_string_literal: true

require "test_helper"

class ContainerStrategies::CustomToolStrategyTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @tool = create(:tool, scope: @company, docker_image: "node:20", command: "node /workspace/main.js")
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

  test "build_cmd uses tool command regardless of tool_files" do
    @tool.tool_files.create!(path: "/workspace/script.py", content: "print('hi')")
    strategy = build_strategy
    cmd = strategy.build_cmd
    assert_equal [ "/bin/sh", "-c", @tool.command ], cmd
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
    assert env.any? { |e| e.start_with?("PALAD_PROJECT_ID=") }
    assert env.any? { |e| e.start_with?("PALAD_PROJECT_NAME=") }
  end

  test "build_labels contains tool metadata" do
    strategy = build_strategy
    labels = strategy.build_labels
    assert_equal "tool_execution", labels["palad.type"]
    assert_equal @tool.id.to_s, labels["palad.tool_id"]
    assert_equal @tool.name, labels["palad.tool_name"]
  end

  test "build_host_config applies resource limits" do
    strategy = build_strategy
    hc = strategy.build_host_config
    assert hc["Memory"].present?
    assert hc["CpuQuota"].present?
    assert_equal false, hc["AutoRemove"]
  end

  test "before_create_container raises without docker_image" do
    @tool.update_column(:docker_image, nil)
    strategy = build_strategy
    assert_raises(ArgumentError, /docker_image/) { strategy.before_create_container }
  end

  private

  def build_strategy(parameters: {}, project: nil)
    ContainerStrategies::CustomToolStrategy.new(
      tool: @tool, parameters: parameters,
      project: project, timeout: 300
    )
  end
end
