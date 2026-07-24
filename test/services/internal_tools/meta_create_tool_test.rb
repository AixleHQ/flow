# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaCreateToolTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    # Standalone (non-workflow) builder session: exposes #project and a nil
    # #step_run, matching what require_project_context!/target_project read.
    project = @project
    @session = Object.new
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { nil }
  end

  test "creates a project-scoped custom tool and returns its identity" do
    result = nil

    assert_difference -> { Tool.count }, 1 do
      result = InternalTools::MetaCreateTool.new(
        params: {
          name: "greeter_bot",
          display_name: "Greeter Bot",
          description: "Greets a user by name",
          docker_image: "alpine:latest",
          command: "echo hi",
          input_schema: { "type" => "object", "properties" => { "who" => { "type" => "string" } } }
        },
        session: @session
      ).execute
    end

    assert_equal 0, result[:exit_code], result[:stderr]
    assert_equal "", result[:stderr]

    payload = JSON.parse(result[:stdout])
    tool = Tool.find(payload["id"])

    # Return payload mirrors the persisted row.
    assert_equal tool.name, payload["name"]
    assert_equal tool.display_name, payload["display_name"]
    assert_equal "greeter_bot", payload["name"]
    assert_equal "Greeter Bot", payload["display_name"]

    # Persisted state: a db-source custom tool scoped to the session project.
    assert tool.persisted?
    assert tool.db_source?
    assert_equal @project, tool.scope
    assert_equal "Project", tool.scope_type
    assert_equal "Greets a user by name", tool.description
    assert_equal "alpine:latest", tool.docker_image
    assert_equal "echo hi", tool.command
    assert_equal({ "type" => "object", "properties" => { "who" => { "type" => "string" } } }, tool.input_schema)
    assert_equal "container", tool.execution_mode
  end

  test "defaults display_name to the titleized name and execution_mode to container" do
    result = InternalTools::MetaCreateTool.new(
      params: { name: "status_check", docker_image: "alpine:latest" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code], result[:stderr]

    tool = Tool.find(JSON.parse(result[:stdout])["id"])
    assert_equal "status_check", tool.name
    assert_equal "Status Check", tool.display_name # name.titleize fallback
    assert_equal "container", tool.execution_mode  # default when omitted
    assert_nil tool.description
    assert_nil tool.command
    assert_equal({}, tool.input_schema)            # {} fallback
    assert_equal @project, tool.scope
  end

  test "creates an app-mode tool scoped to the session project" do
    result = nil

    assert_difference -> { Tool.count }, 1 do
      result = InternalTools::MetaCreateTool.new(
        params: {
          name: "project_wide",
          docker_image: "alpine:latest",
          execution_mode: "app"
        },
        session: @session
      ).execute
    end

    assert_equal 0, result[:exit_code], result[:stderr]

    tool = Tool.find(JSON.parse(result[:stdout])["id"])
    assert_equal @project, tool.scope
    assert_equal "Project", tool.scope_type
    assert_equal "app", tool.execution_mode
  end

  test "normalizes a non-snake-case name to a valid tool name" do
    result = InternalTools::MetaCreateTool.new(
      params: { name: "My Cool Tool", docker_image: "alpine:latest" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code], result[:stderr]

    tool = Tool.find(JSON.parse(result[:stdout])["id"])
    # Tool#name= downcases and replaces every non [a-z0-9_] run with "_".
    assert_equal "my_cool_tool", tool.name
    assert tool.valid?, tool.errors.full_messages.to_sentence
  end
end
