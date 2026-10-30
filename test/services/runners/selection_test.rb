# frozen_string_literal: true

require "test_helper"

class Runners::SelectionTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user, name: "Payments")
    @runner = create(:runner, company: @company, created_by: @user, name: "Prod VPC")
  end

  test "without the flag every pick is refused, hosted included" do
    with_feature(:external_runners, false, company: @company) do
      assert_equal "External runners are not enabled for this company.", Runners::Selection.error(@runner.id, project: @project)
      assert_equal "External runners are not enabled for this company.", Runners::Selection.error(nil, project: @project)
    end
  end

  test "with the flag a visible runner or hosted may be picked, and a disabled one too" do
    with_feature(:external_runners, true, company: @company) do
      assert_nil Runners::Selection.error(@runner.id, project: @project)
      assert_nil Runners::Selection.error(nil, project: @project)

      @runner.disable!
      assert_nil Runners::Selection.error(@runner.id, project: @project)
    end
  end

  test "a deleted runner, or one of another project or company, cannot be picked" do
    other_project_runner = create(:runner, :project_runner, company: @company, created_by: @user)
    foreign = create(:runner)
    deleted = create(:runner, company: @company, created_by: @user)
    deleted.soft_delete!

    with_feature(:external_runners, true, company: @company) do
      [ other_project_runner, foreign, deleted ].each do |runner|
        assert_equal "Runner #{runner.id} is not available to project Payments.",
                     Runners::Selection.error(runner.id, project: @project)
      end
    end
  end

  test "an interactive session cannot pick a runner yet" do
    with_feature(:external_runners, true, company: @company) do
      assert_equal "Runner \"Prod VPC\" can't run interactive sessions yet.",
                   Runners::Selection.error(@runner.id, project: @project, interactive: true)
      assert_nil Runners::Selection.error(nil, project: @project, interactive: true)
    end
  end

  test "a workflow's runner is checked only when it changes" do
    workflow = create(:workflow, scope: @project, runner: @runner)
    other = create(:runner, company: @company, created_by: @user)
    @runner.soft_delete!

    with_feature(:external_runners, false, company: @company) do
      assert_nil Runners::Selection.workflow_error(workflow, @runner.id)
      assert_equal "External runners are not enabled for this company.", Runners::Selection.workflow_error(workflow, other.id)
    end
  end

  test "without the flag a workflow can still be switched back to hosted" do
    workflow = create(:workflow, scope: @project, runner: @runner)

    with_feature(:external_runners, false, company: @company) do
      assert_nil Runners::Selection.workflow_error(workflow, nil)
      assert_nil Runners::Selection.workflow_error(workflow, "")
      assert_equal "External runners are not enabled for this company.", Runners::Selection.error(nil, project: @project)
    end
  end
end
