# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Company
      class MCPServersControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, :admin, company: @company)
          sign_in @user

          Rails.logger.stubs(:info)
          Rails.logger.stubs(:warn)
        end

        # == Index Tests ==

        test "index returns merged servers for company" do
          # Create company-level MCP server
          server = create(:mcp_server, scope: @company, kind: :custom)

          get :index

          assert_response :success
        end

        test "index returns servers list" do
          get :index

          assert_response :success
        end

        # == Create Tests ==

        test "create creates new custom MCP server" do
          assert_difference "MCPServer.count", 1 do
            post :create, params: {
              mcp_server: {
                name: "custom-server",
                display_name: "Custom Server",
                url: "http://localhost:3000",
                transport: "sse",
                description: "Test server",
                enabled: true
              }
            }
          end

          assert_response :created
          # Response goes through serializer
          server = MCPServer.last
          assert_equal "custom-server", server.name
          assert_equal "custom", server.kind
        end

        test "create sets headers when provided" do
          post :create, params: {
            mcp_server: {
              name: "server-with-headers",
              display_name: "Server With Headers",
              url: "http://localhost:3000",
              transport: "sse",
              headers: { "Authorization" => "Bearer token" }
            }
          }

          assert_response :created
          server = MCPServer.last
          assert_equal({ "Authorization" => "Bearer token" }, server.headers)
        end

        test "create returns errors for invalid params" do
          post :create, params: {
            mcp_server: { name: "" }
          }

          assert_response :unprocessable_entity
        end

        # == Update Tests ==

        test "update updates server attributes" do
          server = create(:mcp_server, scope: @company, kind: :custom, name: "old-name")

          put :update, params: {
            id: server.id,
            mcp_server: { display_name: "New Display Name" }
          }

          assert_response :success
          server.reload
          assert_equal "New Display Name", server.display_name
        end

        test "update returns not found for other company's server" do
          other_company = create(:company)
          other_server = create(:mcp_server, scope: other_company, kind: :custom)

          put :update, params: {
            id: other_server.id,
            mcp_server: { display_name: "Hacked" }
          }

          assert_response :not_found
        end

        # == Destroy Tests ==

        test "destroy removes server" do
          server = create(:mcp_server, scope: @company, kind: :custom)

          assert_difference "MCPServer.count", -1 do
            delete :destroy, params: { id: server.id }
          end

          assert_response :success
        end

        test "destroy returns not found for other company's server" do
          other_company = create(:company)
          other_server = create(:mcp_server, scope: other_company, kind: :custom)

          delete :destroy, params: { id: other_server.id }

          assert_response :not_found
        end
      end
    end
  end
end
