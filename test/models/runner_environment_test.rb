# frozen_string_literal: true

require "test_helper"

class RunnerEnvironmentTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :manual)
  end

  test "takes its runner's company" do
    environment = RunnerEnvironment.create!(runner: @runner, key: "aixle-r1-a", origin: :registered, state: :registered,
                                            display_name: "build-01")

    assert_equal @runner.company, environment.company
  end

  test "a registered machine needs a name, and an ephemeral one is refused" do
    environment = build(:runner_environment, runner: @runner, display_name: nil, ephemeral: true)

    assert_not environment.valid?
    assert environment.errors.added?(:display_name, :blank)
    assert environment.errors.of_kind?(:ephemeral, :inclusion)
  end

  test "facts are an object" do
    environment = build(:runner_environment, runner: @runner, facts: [ "docker" ])

    assert_not environment.valid?
    assert_includes environment.errors[:facts], "must be an object"
  end

  test "the database ties an environment to its runner's company and a credential to its environment's runner" do
    other_company = create(:company)
    assert_raises(ActiveRecord::InvalidForeignKey) do
      build(:runner_environment, runner: @runner, company: other_company).save!(validate: false)
    end

    other_environment = create(:runner_environment, runner: create(:runner, :manual, company: @runner.company))
    assert_raises(ActiveRecord::InvalidForeignKey) do
      RunnerCredential.new(runner: @runner, company: @runner.company, runner_environment: other_environment, kind: :access,
                           token_digest: "x", family_id: SecureRandom.uuid, expires_at: 1.hour.from_now).save!(validate: false)
    end
  end
end
