# frozen_string_literal: true

require "test_helper"

class SubStepTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @project = create(:project, company: @company, owner: create(:user, company: @company))
    @workflow = create(:workflow, scope: @project)
    @step = create(:step, workflow: @workflow, position: 1)
  end

  test "valid with required attributes" do
    sub_step = build(:sub_step, step: @step, position: 1)
    assert sub_step.valid?
  end

  test "invalid without name" do
    sub_step = build(:sub_step, step: @step, name: nil)
    assert_not sub_step.valid?
  end

  test "invalid without position" do
    sub_step = build(:sub_step, step: @step, position: nil)
    assert_not sub_step.valid?
  end

  test "allows duplicate position per step" do
    create(:sub_step, step: @step, position: 1)
    duplicate = build(:sub_step, step: @step, position: 1)
    assert duplicate.valid?
  end

  test "ordered by position by default" do
    create(:sub_step, step: @step, position: 2, name: "Second")
    create(:sub_step, step: @step, position: 1, name: "First")
    names = @step.sub_steps.pluck(:name)
    assert_equal %w[First Second], names
  end

  test "required defaults to true" do
    sub_step = create(:sub_step, step: @step, position: 1)
    assert sub_step.required
  end

  test "soft_delete! sets deleted_at" do
    sub_step = create(:sub_step, step: @step, position: 1)
    assert_nil sub_step.deleted_at
    sub_step.soft_delete!
    assert_not_nil sub_step.reload.deleted_at
  end

  test "deleted? returns true after soft delete" do
    sub_step = create(:sub_step, step: @step, position: 1)
    sub_step.soft_delete!
    assert sub_step.deleted?
  end

  test "destroy performs soft delete instead of hard delete" do
    sub_step = create(:sub_step, step: @step, position: 1)
    sub_step.destroy
    assert_not_nil sub_step.reload.deleted_at
    assert SubStep.unscoped.exists?(sub_step.id)
  end

  test "default scope excludes soft-deleted records" do
    active = create(:sub_step, step: @step, position: 1, name: "Active")
    deleted = create(:sub_step, step: @step, position: 2, name: "Deleted")
    deleted.soft_delete!
    assert_includes @step.sub_steps, active
    assert_not_includes @step.sub_steps, deleted
  end

  test "destroy does not raise FK violation when sub_step_runs exist" do
    sub_step = create(:sub_step, step: @step, position: 1)
    step_run = create(:step_run, step: @step)
    create(:sub_step_run, sub_step: sub_step, step_run: step_run)
    assert_nothing_raised { sub_step.destroy }
    assert_not_nil sub_step.reload.deleted_at
  end
end
