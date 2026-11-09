# frozen_string_literal: true

require "test_helper"

# Runners::Save: the adapter's capabilities, an unavailable type and the
# unique-name race. The config checks are the model's (test/models/runner_test.rb).
class Runners::SaveTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
  end

  test "a runner is saved with the capabilities its adapter derives" do
    runner = build(:runner, :manual, company: @company, created_by: @user)

    assert Runners::Save.call(runner)
    assert_equal({ "provisionable" => false, "rebuildable" => false }, runner.reload.capabilities)
  end

  test "a config that breaks a type rule is refused with the rule's message, and nothing is saved" do
    runner = build(:runner, :manual, company: @company, created_by: @user, config: {
      "container" => { "extra_mounts" => [ { "source" => "/srv/out", "target" => "/out", "writable" => true } ] }
    })

    assert_not Runners::Save.call(runner)
    assert_equal [ "container.acknowledged_writable_mounts must list /out: it is a writable host mount" ], runner.errors[:config]
    assert_not runner.persisted?
  end

  test "a type without an adapter is refused, with the model's other errors" do
    runner = build(:runner, :kubernetes, company: @company, created_by: @user, name: "")

    assert_not Runners::Save.call(runner)
    assert_includes runner.errors[:runner_type], "is not available yet"
    assert runner.errors.added?(:name, :blank)
    assert_equal 0, Runner.count
  end

  test "a name taken by a concurrent save is an error on name" do
    runner = build(:runner, :manual, company: @company, created_by: @user)
    runner.stubs(:save).raises(ActiveRecord::RecordNotUnique)

    assert_not Runners::Save.call(runner)
    assert runner.errors.added?(:name, :taken)
  end
end
