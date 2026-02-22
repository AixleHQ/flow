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

  test "unique position per step" do
    create(:sub_step, step: @step, position: 1)
    duplicate = build(:sub_step, step: @step, position: 1)
    assert_not duplicate.valid?
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
end
