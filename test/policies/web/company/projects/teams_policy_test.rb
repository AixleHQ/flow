# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    module Projects
      class TeamsPolicyTest < ActiveSupport::TestCase
        setup do
          @company = create(:company)
          @owner = create(:user, :employee, company: @company)
          @project = create(:project, company: @company, owner: @owner)
        end

        def policy_for(user)
          TeamsPolicy.new(ProjectContext.new(user, {}, project: @project), :teams)
        end

        def collaborator_with(*traits, **attrs)
          create(:user, *traits, company: @company, **attrs).tap { |u| @project.add_collaborator(u) }
        end

        test "the owner and a company admin manage teams" do
          [ @owner, create(:user, :admin, company: @company) ].each do |user|
            policy = policy_for(user)
            assert [ policy.index?, policy.create?, policy.update?, policy.destroy?, policy.leave? ].all?
          end
        end

        test "a collaborator and a viewer see teams and may leave one, but not change them" do
          viewer = collaborator_with(:viewer, email: "client-#{SecureRandom.hex(3)}@external.com")
          [ collaborator_with(:employee), viewer ].each do |user|
            policy = policy_for(user)
            assert policy.index?
            assert policy.leave?
            assert_not policy.create?
            assert_not policy.update?
            assert_not policy.destroy?
          end
        end

        test "an outsider gets nothing" do
          policy = policy_for(create(:user, :admin, company: create(:company)))
          assert_not policy.index?
          assert_not policy.manage?
        end
      end
    end
  end
end
