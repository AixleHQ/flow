# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    module Projects
      # The catalog must not become a way around the manual MCP form's checks,
      # so this asserts the two policies agree rather than merely that this one
      # behaves plausibly.
      class ConnectorsPolicyTest < ActiveSupport::TestCase
        setup do
          @company = create(:company)
          @owner = create(:user, company: @company)
          @project = create(:project, company: @company, owner: @owner)
        end

        def context_for(user)
          ProjectContext.new(user, {}, project: @project)
        end

        def policy_for(user)
          ConnectorsPolicy.new(context_for(user), :connectors)
        end

        test "a project owner may install" do
          assert_predicate policy_for(@owner), :create?
        end

        test "a viewer may not install" do
          viewer = create(:user, company: @company, membership_role: :viewer)
          create(:project_collaborator, project: @project, user: viewer)

          assert_not policy_for(viewer).create?
        end

        test "a user outside the project may not install" do
          assert_not policy_for(create(:user)).create?
        end

        # Browsing is gated by MCPServersPolicy (the catalog is served with that
        # page); only installing lives here, and it must match the manual form.
        test "install permission matches the manual MCP server form exactly" do
          viewer = create(:user, company: @company, membership_role: :viewer)
          create(:project_collaborator, project: @project, user: viewer)

          [ @owner, viewer, create(:user) ].each do |user|
            connectors = ConnectorsPolicy.new(context_for(user), :connectors)
            manual = MCPServersPolicy.new(context_for(user), :mcp_servers)

            assert_equal manual.create?, connectors.create?, "create? diverged for #{user.id}"
          end
        end
      end
    end
  end
end
