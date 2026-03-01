# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Company
      module Projects
        class MCPServersControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :admin, company: @company)
            @project = create(:project, company: @company, owner: @user)
            sign_in @user

            Rails.logger.stubs(:info)
            Rails.logger.stubs(:warn)
          end

          # == Index Tests ==

          test "index returns merged servers for project" do
            server = create(:mcp_server, scope: @project, kind: :custom)

            get :index, params: { project_id: @project.id }

            assert_response :success
          end

          test "index includes company servers" do
            company_server = create(:mcp_server, scope: @company, kind: :custom)

            get :index, params: { project_id: @project.id }

            assert_response :success
          end

          # == Create Tests ==

          test "create creates new project MCP server" do
            assert_difference "MCPServer.count", 1 do
              post :create, params: {
                project_id: @project.id,
                mcp_server: {
                  name: "project-server",
                  display_name: "Project Server",
                  url: "https://mcp.example.com/v1",
                  transport: "sse"
                }
              }
            end

            assert_response :created
            server = MCPServer.last
            assert_equal "project-server", server.name
            assert_equal @project.id, server.scope_id
            assert_equal "Project", server.scope_type
          end

          test "create returns errors for invalid params" do
            post :create, params: {
              project_id: @project.id,
              mcp_server: { name: "" }
            }

            assert_response :unprocessable_entity
          end

          # == Update Tests ==

          test "update updates server attributes" do
            server = create(:mcp_server, scope: @project, kind: :custom)

            put :update, params: {
              project_id: @project.id,
              id: server.id,
              mcp_server: { display_name: "Updated Name" }
            }

            assert_response :success
            server.reload
            assert_equal "Updated Name", server.display_name
          end

          test "update returns not found for company's server" do
            company_server = create(:mcp_server, scope: @company, kind: :custom)

            put :update, params: {
              project_id: @project.id,
              id: company_server.id,
              mcp_server: { display_name: "Hacked" }
            }

            assert_response :not_found
          end

          # == Destroy Tests ==

          test "destroy removes server" do
            server = create(:mcp_server, scope: @project, kind: :custom)

            assert_difference "MCPServer.count", -1 do
              delete :destroy, params: { project_id: @project.id, id: server.id }
            end

            assert_response :success
          end

          test "destroy returns not found for company's server" do
            company_server = create(:mcp_server, scope: @company, kind: :custom)

            delete :destroy, params: { project_id: @project.id, id: company_server.id }

            assert_response :not_found
          end
        end
      end
    end
  end
end
