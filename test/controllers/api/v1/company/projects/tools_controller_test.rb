# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Company
      module Projects
        class ToolsControllerTest < ActionDispatch::IntegrationTest
          setup do
            @company = create(:company)
            @owner = create(:user, :employee, company: @company)
            @member = create(:user, :employee, company: @company)
            @outsider = create(:user, :employee, company: create(:company))

            @project = create(:project, company: @company, owner: @owner)
            @project.add_collaborator(@member)

            # Create some tools
            @internal_tool = create(:tool, :internal, name: "internal_tool")
            @company_tool = create(:tool, name: "company_tool", scope: @company, docker_image: "python:3.11")
            @project_tool = create(:tool, :project, name: "project_tool", scope: @project, docker_image: "node:18")
          end

          # --- Index (Merged List) ---
          test "index returns merged list" do
            sign_in_as @member
            get api_v1_company_project_tools_path(@project)

            assert_response :success
            tools = response.parsed_body["items"]

            assert_equal 3, tools.count
            names = tools.map { |t| t["name"] }
            assert_includes names, "internal_tool"
            assert_includes names, "company_tool"
            assert_includes names, "project_tool"
          end

          test "index returns correct scope_indicators" do
            sign_in_as @member
            get api_v1_company_project_tools_path(@project)

            assert_response :success
            tools = response.parsed_body["items"]

            internal = tools.find { |t| t["name"] == "internal_tool" }
            company = tools.find { |t| t["name"] == "company_tool" }
            project = tools.find { |t| t["name"] == "project_tool" }

            assert_equal "system", internal["scope_indicator"]
            assert_equal "company", company["scope_indicator"]
            assert_equal "project", project["scope_indicator"]
          end

          test "index shows override indicator when project overrides company" do
            # Create project tool with same name as company tool
            create(:tool, :project, name: "company_tool", scope: @project, docker_image: "overridden:image")

            sign_in_as @member
            get api_v1_company_project_tools_path(@project)

            assert_response :success
            tools = response.parsed_body["items"]

            company_tools = tools.select { |t| t["name"] == "company_tool" }
            assert_equal 2, company_tools.count
            project_version = company_tools.find { |t| t["scope_type"] == "Project" }
            assert_equal "overrides_company", project_version["scope_indicator"]
            assert_equal "overridden:image", project_version["docker_image"]
          end

          test "index fails for outsider" do
            sign_in_as @outsider
            get api_v1_company_project_tools_path(@project)

            assert_response :not_found
          end

          # --- Create ---
          test "create project tool" do
            sign_in_as @member

            assert_difference "Tool.count" do
              post api_v1_company_project_tools_path(@project), params: {
                tool: {
                  name: "new_project_tool",
                  display_name: "New Project Tool",
                  docker_image: "ruby:3.2"
                }
              }
            end

            assert_response :created
            tool = response.parsed_body["data"]
            assert_equal "new_project_tool", tool["name"]
            assert_equal "Project", tool["scope_type"]
            assert_equal @project.id, tool["scope_id"]
          end

          test "create with nested tool_files" do
            sign_in_as @member

            post api_v1_company_project_tools_path(@project), params: {
              tool: {
                name: "with_files",
                display_name: "With Files",
                docker_image: "python:3.11",
                tool_files_attributes: [
                  { path: "/workspace/main.py", content: "import sys" }
                ]
              }
            }

            assert_response :created
            tool = response.parsed_body["data"]
            assert_equal 1, tool["tool_files"].count
            assert_equal "/workspace/main.py", tool["tool_files"].first["path"]
          end

          test "create fails for outsider" do
            sign_in_as @outsider

            post api_v1_company_project_tools_path(@project), params: {
              tool: {
                name: "new_tool",
                display_name: "New",
                docker_image: "alpine"
              }
            }

            assert_response :not_found
          end

          # --- Update ---
          test "update project tool" do
            sign_in_as @member

            patch api_v1_company_project_tool_path(@project, @project_tool), params: {
              tool: {
                display_name: "Updated Project Tool"
              }
            }

            assert_response :success
            assert_equal "Updated Project Tool", response.parsed_body["data"]["display_name"]
          end

          test "update fails for outsider" do
            sign_in_as @outsider

            patch api_v1_company_project_tool_path(@project, @project_tool), params: {
              tool: { display_name: "Hacked" }
            }

            assert_response :not_found
          end

          # --- Destroy ---
          test "destroy project tool" do
            sign_in_as @member

            assert_difference "Tool.count", -1 do
              delete api_v1_company_project_tool_path(@project, @project_tool)
            end

            assert_response :no_content
          end

          test "destroy fails for outsider" do
            sign_in_as @outsider

            delete api_v1_company_project_tool_path(@project, @project_tool)

            assert_response :not_found
          end
        end
      end
    end
  end
end
