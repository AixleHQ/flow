# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ReadOnlyPoliciesTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @owner = create(:user, :employee, :onboarding_completed, company: @company)
        @project = create(:project, company: @company, owner: @owner)

        @viewer = create(:user, :viewer, company: @company, email: "client@external.com")
        @project.add_collaborator(@viewer)

        @employee = create(:user, :employee, :onboarding_completed, company: @company)
        @project.add_collaborator(@employee)

        @outsider = create(:user, :employee, :onboarding_completed, company: @company)
      end

      def project_ctx(user)
        ProjectContext.new(user, {}, project: @project)
      end

      def base_ctx(user)
        BaseContext.new(user, {})
      end

      # === project-scoped ===

      test "Projects::Board::TasksPolicy classification" do
        v = Projects::Board::TasksPolicy.new(project_ctx(@viewer), nil)
        assert v.index?
        assert v.show?
        assert v.workflow_runs?
        assert_not v.create?
        assert_not v.update?
        assert_not v.destroy?
        assert_not v.move?
        assert_not v.trigger_workflow?

        e = Projects::Board::TasksPolicy.new(project_ctx(@employee), nil)
        assert e.create?
        assert e.trigger_workflow?

        o = Projects::Board::TasksPolicy.new(project_ctx(@outsider), nil)
        assert_not o.index?
        assert_not o.create?
      end

      test "Projects::AssetsPolicy classification" do
        v = Projects::AssetsPolicy.new(project_ctx(@viewer), nil)
        assert v.download?
        assert_not v.create?
        assert_not v.destroy?
        assert Projects::AssetsPolicy.new(project_ctx(@employee), nil).create?
      end

      test "Projects::WorkflowsPolicy classification" do
        v = Projects::WorkflowsPolicy.new(project_ctx(@viewer), nil)
        assert v.show?
        assert_not v.update?
        assert_not v.destroy?
      end

      test "Projects::Workflows::StepsPolicy classification" do
        v = Projects::Workflows::StepsPolicy.new(project_ctx(@viewer), nil)
        assert v.index?
        assert_not v.create?
        assert_not v.reorder?
      end

      test "Projects::Workflows::TriggersPolicy classification" do
        v = Projects::Workflows::TriggersPolicy.new(project_ctx(@viewer), nil)
        assert v.index?
        assert_not v.create?
        assert_not v.destroy?
      end

      test "Projects::Board::ColumnsPolicy: viewer denied writes" do
        v = Projects::Board::ColumnsPolicy.new(project_ctx(@viewer), nil)
        assert v.index?
        assert_not v.create?
        assert_not v.reorder?
      end

      test "Projects::Board::Columns::WorkflowBindingsPolicy classification" do
        v = Projects::Board::Columns::WorkflowBindingsPolicy.new(project_ctx(@viewer), nil)
        assert v.show?
        assert_not v.create?
        assert_not v.destroy?
      end

      test "Projects::Board::ViewPresetsPolicy classification" do
        v = Projects::Board::ViewPresetsPolicy.new(project_ctx(@viewer), nil)
        assert v.index?
        assert_not v.create?
        assert_not v.destroy?
      end

      test "Projects::Board::Task::CommentsPolicy classification" do
        v = Projects::Board::Task::CommentsPolicy.new(project_ctx(@viewer), nil)
        assert v.index?
        assert_not v.create?
      end

      test "Projects::Board::Task::AssetsPolicy classification" do
        v = Projects::Board::Task::AssetsPolicy.new(project_ctx(@viewer), nil)
        assert v.index?
        assert_not v.create?
        assert_not v.destroy?
      end

      test "Projects::Board::Task::GatesPolicy classification" do
        v = Projects::Board::Task::GatesPolicy.new(project_ctx(@viewer), nil)
        assert_not v.destroy?
        assert Projects::Board::Task::GatesPolicy.new(project_ctx(@employee), nil).destroy?
      end

      test "Projects::WorkflowRunAssetsPolicy: export is write, index/download are read" do
        v = Projects::WorkflowRunAssetsPolicy.new(project_ctx(@viewer), nil)
        assert v.index?
        assert v.download?
        assert_not v.export?
        assert_not v.export_all?
      end

      test "Projects::BoardPolicy: viewer denied writes" do
        v = Projects::BoardPolicy.new(project_ctx(@viewer), nil)
        assert_not v.create?
        assert_not v.create_from_preset?
      end

      # === non-project-scoped ===

      test "AssetsPolicy (top-level upload): viewer denied" do
        v = AssetsPolicy.new(base_ctx(@viewer), nil)
        assert_not v.presign?
        assert_not v.upload?
        assert AssetsPolicy.new(base_ctx(@employee), nil).upload?
      end

      test "Company::AssetsPolicy classification" do
        v = Company::AssetsPolicy.new(base_ctx(@viewer), nil)
        assert v.download?
        assert_not v.create?
        assert_not v.destroy?
        assert Company::AssetsPolicy.new(base_ctx(@employee), nil).create?
      end

      test "TerminalSessionsPolicy classification" do
        v = TerminalSessionsPolicy.new(base_ctx(@viewer), nil)
        assert v.show?
        assert_not v.create?
        assert_not v.finish?
        assert TerminalSessionsPolicy.new(base_ctx(@employee), nil).create?
      end
    end
  end
end
