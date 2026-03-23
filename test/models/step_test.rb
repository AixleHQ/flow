# frozen_string_literal: true

require "test_helper"

class StepTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @project = create(:project, company: @company, owner: create(:user, company: @company))
    @workflow = create(:workflow, scope: @project)
  end

  test "valid with required attributes" do
    step = build(:step, workflow: @workflow, position: 1)
    assert step.valid?
  end

  test "invalid without name" do
    step = build(:step, workflow: @workflow, name: nil)
    assert_not step.valid?
  end

  test "invalid without position" do
    step = build(:step, workflow: @workflow, position: nil)
    assert_not step.valid?
  end

  test "unique position per workflow" do
    create(:step, workflow: @workflow, position: 1)
    duplicate = build(:step, workflow: @workflow, position: 1)
    assert_not duplicate.valid?
  end

  test "same position in different workflows" do
    other = create(:workflow, scope: @project)
    create(:step, workflow: @workflow, position: 1)
    step = build(:step, workflow: other, position: 1)
    assert step.valid?
  end

  test "ordered by position by default" do
    create(:step, workflow: @workflow, position: 3, name: "Third")
    create(:step, workflow: @workflow, position: 1, name: "First")
    create(:step, workflow: @workflow, position: 2, name: "Second")
    names = @workflow.steps.pluck(:name)
    assert_equal %w[First Second Third], names
  end

  test "enumerize skip_policy" do
    step = build(:step, workflow: @workflow, skip_policy: :manual)
    assert_equal "manual", step.skip_policy
  end

  test "enumerize on_failure" do
    step = build(:step, workflow: @workflow, on_failure: :retry)
    assert_equal "retry", step.on_failure
  end

  test "agent is optional" do
    step = build(:step, workflow: @workflow, agent: nil)
    assert step.valid?
  end

  test "nested sub_steps via accepts_nested_attributes" do
    step = create(:step, workflow: @workflow, position: 1, sub_steps_attributes: [
      { name: "Sub 1", position: 1 },
      { name: "Sub 2", position: 2 }
    ])
    assert_equal 2, step.sub_steps.count
  end

  test "destroying step destroys sub_steps" do
    step = create(:step, workflow: @workflow, position: 1)
    create(:sub_step, step: step, position: 1)
    assert_difference "SubStep.count", -1 do
      step.destroy
    end
  end

  test "destroy returns false when another active step depends on it" do
    step_a = create(:step, workflow: @workflow, position: 1)
    create(:step, workflow: @workflow, position: 2, depends_on_step_ids: [step_a.id])

    result = step_a.destroy
    assert_equal false, result
    assert step_a.errors[:base].any?
    assert Step.exists?(step_a.id)
  end

  test "destroy succeeds when dependent step is already soft-deleted" do
    step_a = create(:step, workflow: @workflow, position: 1)
    step_b = create(:step, workflow: @workflow, position: 2, depends_on_step_ids: [step_a.id])
    step_b.soft_delete!

    assert_difference "Step.count", -1 do
      step_a.destroy
    end
  end
end
