# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Company
      class ToolsControllerTest < ActionDispatch::IntegrationTest
        setup do
          @company = create(:company)
          @admin = create(:user, :admin, company: @company)
          @member = create(:user, :employee, company: @company)

          # Create some tools
          @internal_tool = create(:tool, :internal, name: "internal_tool")
          @company_tool = create(:tool, name: "company_tool", scope: @company, docker_image: "python:3.11")
        end

        # --- Index ---
        test "index returns merged list (internal + company)" do
          sign_in_as @admin
          get api_v1_company_tools_path

          assert_response :success
          tools = response.parsed_body["items"]

          assert_equal 2, tools.count
          names = tools.map { |t| t["name"] }
          assert_includes names, "internal_tool"
          assert_includes names, "company_tool"
        end

        test "index returns scope_indicator" do
          sign_in_as @admin
          get api_v1_company_tools_path

          assert_response :success
          tools = response.parsed_body["items"]

          internal = tools.find { |t| t["name"] == "internal_tool" }
          company = tools.find { |t| t["name"] == "company_tool" }

          assert_equal "system", internal["scope_indicator"]
          assert_equal "company", company["scope_indicator"]
        end

        test "index fails for non-admin" do
          sign_in_as @member
          get api_v1_company_tools_path

          assert_response :forbidden
        end

        # --- Create ---
        test "create company tool" do
          sign_in_as @admin

          assert_difference "Tool.count" do
            post api_v1_company_tools_path, params: {
              tool: {
                name: "new_tool",
                display_name: "New Tool",
                docker_image: "node:18",
                command: "node /app/script.js"
              }
            }
          end

          assert_response :created
          tool = response.parsed_body["data"]
          assert_equal "new_tool", tool["name"]
          assert_equal "Company", tool["scope_type"]
          assert_equal @company.id, tool["scope_id"]
        end

        test "create with tool_files" do
          sign_in_as @admin

          post api_v1_company_tools_path, params: {
            tool: {
              name: "tool_with_files",
              display_name: "Tool with Files",
              docker_image: "python:3.11",
              tool_files_attributes: [
                { path: "/workspace/script.py", content: "print('hello')" },
                { path: "/workspace/config.yaml", content: "key: value" }
              ]
            }
          }

          assert_response :created
          tool = response.parsed_body["data"]
          assert_equal 2, tool["tool_files"].count
        end

        test "create auto-downcases name" do
          sign_in_as @admin

          post api_v1_company_tools_path, params: {
            tool: {
              name: "MY_TOOL",
              display_name: "My Tool",
              docker_image: "alpine"
            }
          }

          assert_response :created
          assert_equal "my_tool", response.parsed_body["data"]["name"]
        end

        test "create validates name format" do
          sign_in_as @admin

          post api_v1_company_tools_path, params: {
            tool: {
              name: "123invalid",
              display_name: "Invalid",
              docker_image: "alpine"
            }
          }

          assert_response :unprocessable_entity
        end

        test "create fails for non-admin" do
          sign_in_as @member

          post api_v1_company_tools_path, params: {
            tool: {
              name: "new_tool",
              display_name: "New Tool",
              docker_image: "alpine"
            }
          }

          assert_response :forbidden
        end

        # --- Update ---
        test "update company tool" do
          sign_in_as @admin

          patch api_v1_company_tool_path(@company_tool), params: {
            tool: {
              display_name: "Updated Display Name"
            }
          }

          assert_response :success
          assert_equal "Updated Display Name", response.parsed_body["data"]["display_name"]
          assert_equal "Updated Display Name", @company_tool.reload.display_name
        end

        test "update fails for non-admin" do
          sign_in_as @member

          patch api_v1_company_tool_path(@company_tool), params: {
            tool: { display_name: "Updated" }
          }

          assert_response :forbidden
        end

        # --- Destroy ---
        test "destroy company tool" do
          sign_in_as @admin

          assert_difference "Tool.count", -1 do
            delete api_v1_company_tool_path(@company_tool)
          end

          assert_response :no_content
        end

        test "destroy fails for non-admin" do
          sign_in_as @member

          delete api_v1_company_tool_path(@company_tool)

          assert_response :forbidden
        end
      end
    end
  end
end
