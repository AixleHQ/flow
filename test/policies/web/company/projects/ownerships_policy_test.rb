# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    module Projects
      class OwnershipsPolicyTest < ActiveSupport::TestCase
        setup do
          @company = create(:company)
          @owner = create(:user, :employee, company: @company)
          @project = create(:project, company: @company, owner: @owner)
        end

        def policy_for(user)
          OwnershipsPolicy.new(ProjectContext.new(user, {}, project: @project), :ownerships)
        end

        def collaborator_with(*traits, **attrs)
          create(:user, *traits, company: @company, **attrs).tap { |u| @project.add_collaborator(u) }
        end

        test "the owner and a company admin may transfer" do
          assert policy_for(@owner).update?
          assert policy_for(create(:user, :admin, company: @company)).update?
        end

        test "the permission follows the owner once the project changes hands" do
          heir = collaborator_with(:employee)
          @project.transfer_ownership_to(heir)

          assert policy_for(heir).update?
          assert_not policy_for(@owner).update?
        end

        test "a collaborator, a viewer and an outsider may not transfer" do
          assert_not policy_for(collaborator_with(:employee)).update?
          assert_not policy_for(collaborator_with(:viewer, email: "client-#{SecureRandom.hex(3)}@external.com")).update?
          assert_not policy_for(create(:user, :admin, company: create(:company))).update?
        end
      end
    end
  end
end
