# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    module Projects
      # Every action the controller exposes is checked here, including the two
      # member actions. `update_connector` shipped without a policy method and
      # the dynamic authorize turned that into a NoMethodError — a 500, not a
      # denial — so "the policy answers at all" is as much the contract as which
      # answer it gives.
      class MCPServersPolicyTest < ActiveSupport::TestCase
        ACTIONS = %i[index? create? update? destroy? update_connector? accept_tool_drift?].freeze
        WRITES = ACTIONS - [ :index? ]

        setup do
          @company = create(:company)
          @owner = create(:user, company: @company)
          @project = create(:project, company: @company, owner: @owner)

          @collaborator = create(:user, company: @company)
          @project.add_collaborator(@collaborator)

          @viewer = create(:user, company: @company, membership_role: :viewer)
          @project.add_collaborator(@viewer)

          @outsider = create(:user)
        end

        def policy_for(user)
          MCPServersPolicy.new(ProjectContext.new(user, {}, project: @project), :mcp_servers)
        end

        test "the owner and a collaborator may read and write every action" do
          [ @owner, @collaborator ].each do |user|
            policy = policy_for(user)
            ACTIONS.each { |action| assert policy.public_send(action), "#{action} denied for #{user.id}" }
          end
        end

        test "a viewer may look but may not change anything" do
          policy = policy_for(@viewer)

          assert policy.index?
          WRITES.each { |action| assert_not policy.public_send(action), "#{action} allowed for a viewer" }
        end

        test "a user outside the project gets nothing" do
          policy = policy_for(@outsider)

          ACTIONS.each { |action| assert_not policy.public_send(action), "#{action} allowed for an outsider" }
        end

        # Both member actions change what an installed server serves — the
        # version it runs, or the tool baseline it is trusted at — so neither may
        # be looser than editing the server by hand.
        test "the member actions are exactly as privileged as update" do
          [ @owner, @collaborator, @viewer, @outsider ].each do |user|
            policy = policy_for(user)

            assert_equal policy.update?, policy.update_connector?, "update_connector? diverged for #{user.id}"
            assert_equal policy.update?, policy.accept_tool_drift?, "accept_tool_drift? diverged for #{user.id}"
          end
        end
      end
    end
  end
end
