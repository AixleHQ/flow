# frozen_string_literal: true

require "test_helper"

class ToolExecutionServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @tool = create(:tool, :with_files, scope: @company, docker_image: "alpine:latest", command: "echo 'hello world'")

    # Create config items
    @api_key = create(:config_item, name: "API_KEY", value: "secret123", scope: @company)
    @tool.update!(required_config_items: [ "API_KEY" ])
  end

  test "raises error for internal tools" do
    internal_tool = create(:tool, :internal, name: "internal_tool")

    assert_raises(ArgumentError) do
      ToolExecutionService.execute(tool: internal_tool)
    end
  end

  test "raises error for tools without docker_image" do
    @tool.update_column(:docker_image, nil)

    assert_raises(ArgumentError) do
      ToolExecutionService.execute(tool: @tool.reload)
    end
  end

  test "resolves config items from company scope" do
    env_vars = ToolExecutionService.send(:resolve_config_items, @tool, nil)

    assert_equal({ "API_KEY" => "secret123" }, env_vars)
  end

  test "resolves config items with project override" do
    project_key = create(:config_item, name: "API_KEY", value: "project_secret", scope: @project)

    env_vars = ToolExecutionService.send(:resolve_config_items, @tool, @project)

    assert_equal({ "API_KEY" => "project_secret" }, env_vars)
  end

  test "base64 encoding for file injection" do
    content = "Hello\nWorld\n!@#$%"
    encoded = Base64.strict_encode64(content)
    decoded = Base64.strict_decode64(encoded)

    assert_equal content, decoded
  end

  test "builds command with parameter substitution" do
    @tool.update!(command: "python {{script}} --env={{env}}")
    params = { script: "main.py", env: "production" }

    command = ToolExecutionService.send(:build_command, @tool, params)

    assert_equal "python main.py --env=production", command
  end

  test "truncates large output" do
    large_output = "x" * (2 * 1024 * 1024) # 2MB

    truncated = ToolExecutionService.send(:truncate_output, large_output)

    assert truncated.bytesize <= ToolExecutionService::MAX_OUTPUT_SIZE + 50
    assert truncated.include?("(truncated)")
  end
end
