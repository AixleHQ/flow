# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    module Projects
      class ReadOnlyPoliciesTest < ActiveSupport::TestCase
        setup do
          @company = create(:company)
          @owner = create(:user, :employee, :onboarding_completed, company: @company)
          @project = create(:project, company: @company, owner: @owner)

          @viewer = create(:user, :viewer, company: @company, email: "client@external.com")
          @project.add_collaborator(@viewer)

          @employee = create(:user, :employee, :onboarding_completed, company: @company)
          @project.add_collaborator(@employee)

          @admin = create(:user, :admin, :onboarding_completed, company: @company)
        end

        def context_for(user)
          ProjectContext.new(user, {}, project: @project)
        end

        test "WorkflowsPolicy: viewer reads allowed, writes denied" do
          p = WorkflowsPolicy.new(context_for(@viewer), nil)
          assert p.index?
          assert p.show?
          assert p.builder?
          assert_not p.create?
          assert_not p.update?
          assert_not p.destroy?
          assert_not p.publish?
          assert_not p.duplicate?
        end

        test "WorkflowsPolicy: employee collaborator can write" do
          p = WorkflowsPolicy.new(context_for(@employee), nil)
          assert p.create?
          assert p.update?
          assert p.destroy?
        end

        test "WorkflowsPolicy: company admin (non-member) can read and write" do
          p = WorkflowsPolicy.new(context_for(@admin), nil)
          assert p.index?
          assert p.create?
        end

        test "WorkflowRunsPolicy: viewer cannot run" do
          p = WorkflowRunsPolicy.new(context_for(@viewer), nil)
          assert p.index?
          assert_not p.create?
          assert_not p.cancel?
          assert_not p.approve_step?
        end

        test "SessionsPolicy: viewer can read, cannot launch (new?)" do
          p = SessionsPolicy.new(context_for(@viewer), nil)
          assert p.index?
          assert p.show?
          assert_not p.new?
        end

        test "AnalyticsPolicy: viewer can read analytics" do
          p = AnalyticsPolicy.new(context_for(@viewer), nil)
          assert p.index?
        end

        test "AssetsPolicy: viewer reads allowed, writes denied" do
          p = AssetsPolicy.new(context_for(@viewer), nil)
          assert p.index?
          assert p.download?
          assert_not p.create?
          assert_not p.destroy?
        end

        test "MembersPolicy: viewer cannot add/remove collaborators" do
          p = MembersPolicy.new(context_for(@viewer), nil)
          assert p.index?
          assert_not p.create?
          assert_not p.destroy?
        end

        test "MembersPolicy: employee collaborator can add/remove" do
          p = MembersPolicy.new(context_for(@employee), nil)
          assert p.create?
          assert p.destroy?
        end

        test "AixleBuilderPolicy: viewer cannot start/finish builds" do
          p = AixleBuilderPolicy.new(context_for(@viewer), nil)
          assert p.show?
          assert_not p.start?
          assert_not p.finish?
        end

        # The one write a viewer IS allowed: their own list ordering. Favoriting
        # touches nothing about the project and nobody else's list.
        test "FavoritesPolicy: viewer can favorite and unfavorite" do
          p = FavoritesPolicy.new(context_for(@viewer), nil)
          assert p.create?
          assert p.destroy?
        end

        test "FavoritesPolicy: a user with no access to the project cannot favorite it" do
          stranger = create(:user, :employee, :onboarding_completed, company: @company)

          p = FavoritesPolicy.new(context_for(stranger), nil)
          assert_not p.create?
          assert_not p.destroy?
        end

        # Repositories used to require the company admin role, which left a
        # project owner able to connect the GitHub integration but not attach a
        # repository from it. They are a plain project write now.
        test "RepositoriesPolicy: project owner without the admin role can write" do
          p = RepositoriesPolicy.new(context_for(@owner), nil)
          assert p.index?
          assert p.create?
          assert p.update?
          assert p.destroy?
        end

        test "RepositoriesPolicy: viewer reads allowed, writes denied" do
          p = RepositoriesPolicy.new(context_for(@viewer), nil)
          assert p.index?
          assert_not p.create?
          assert_not p.update?
          assert_not p.destroy?
        end

        test "AgentsPolicy/ToolsPolicy: viewer writes denied" do
          assert_not AgentsPolicy.new(context_for(@viewer), nil).create?
          assert_not ToolsPolicy.new(context_for(@viewer), nil).create?
          assert AgentsPolicy.new(context_for(@viewer), nil).index?
        end
      end
    end
  end
end
