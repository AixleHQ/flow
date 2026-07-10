# frozen_string_literal: true

require "test_helper"

module Coder
  class MCPServerSyncServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user    = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
    end

    test "creates a managed MCP server for a company-wide integration" do
      integration = create(:integration, :coder, :active, company: @company, connected_by: @user)

      server = Coder::MCPServerSyncService.new(integration).sync!

      assert server.persisted?
      assert server.managed?
      assert_equal integration, server.integration
      assert_equal "coder-#{integration.id}", server.name
      assert_equal "Company", server.scope_type
      assert_equal @company.id, server.scope_id
      assert server.enabled
    end

    test "creates a managed MCP server scoped to the project for project-scoped integration" do
      integration = create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)

      server = Coder::MCPServerSyncService.new(integration).sync!

      assert_equal "Project", server.scope_type
      assert_equal @project.id, server.scope_id
    end

    test "is idempotent — re-running updates the existing row in place" do
      integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      first  = Coder::MCPServerSyncService.new(integration).sync!
      second = Coder::MCPServerSyncService.new(integration).sync!

      assert_equal first.id, second.id
      assert_equal 1, MCPServer.for_integration(integration).count
    end

    test "disables the MCP server when the integration is in error state" do
      integration = create(:integration, :coder, :error, company: @company, connected_by: @user)
      server = Coder::MCPServerSyncService.new(integration).sync!

      assert_not server.enabled
    end

    test "re-enables the MCP server after the integration recovers" do
      integration = create(:integration, :coder, :error, company: @company, connected_by: @user)
      server = Coder::MCPServerSyncService.new(integration).sync!
      assert_not server.enabled

      integration.update!(status: :active)
      Coder::MCPServerSyncService.new(integration).sync!

      assert server.reload.enabled
    end

    test "rejects a non-Coder integration" do
      integration = create(:integration, :github, company: @company, connected_by: @user)

      assert_raises ArgumentError do
        Coder::MCPServerSyncService.new(integration).sync!
      end
    end
  end
end
