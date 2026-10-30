# frozen_string_literal: true

require "test_helper"

class RunnerOperationTest < ActiveSupport::TestCase
  setup do
    @environment = create(:runner_environment)
  end

  test "the payload is stored encrypted with runners_key" do
    operation = build_operation(payload: { "content" => "s3cr3t-token" })
    operation.save!

    stored = RunnerOperation.connection.select_value(
      RunnerOperation.where(id: operation.id).select(:encrypted_payload).to_sql
    )
    assert_not_includes stored, "s3cr3t-token"
    assert_equal({ "content" => "s3cr3t-token" }, RunnerOperation.find(operation.id).payload)

    with_runners_key("another-runners-key-0123456789abcdef") do
      assert_raises(Encryptable::DecryptionError) { RunnerOperation.find(operation.id).payload }
    end
  end

  test "without runners_key only encrypting or decrypting a payload fails" do
    with_runners_key(nil) do
      operation = build_operation(payload: nil)
      assert operation.valid?
      error = assert_raises(ArgumentError) { operation.payload = { "cmd" => "true" } }
      assert_match(/RunnerOperation encryption key is not set/, error.message)
    end
  end

  test "an op takes its environment's runner and company, and the op is one of §6.4's environment ops" do
    operation = build_operation(op: "provision")

    assert_not operation.valid?
    assert operation.errors.of_kind?(:op, :inclusion)
    assert_equal [ @environment.runner_id, @environment.company_id ], [ operation.runner_id, operation.company_id ]
  end

  test "the database ties an op to its environment's runner and to that runner's company" do
    other_runner = create(:runner, :manual, company: @environment.company)
    assert_raises(ActiveRecord::InvalidForeignKey) do
      build_operation(runner: other_runner, company: @environment.company).save!(validate: false)
    end

    assert_raises(ActiveRecord::InvalidForeignKey) do
      build_operation(runner: @environment.runner, company: create(:company)).save!(validate: false)
    end
  end

  test "an environment's ops go with it" do
    build_operation.save!

    @environment.runner.destroy!

    assert_equal 0, RunnerOperation.count
  end

  private

  def build_operation(payload: { "cmd" => "true" }, **attributes)
    RunnerOperation.new({ runner_environment: @environment, sequence: 1, op: "exec", state: :pending,
                          deadline_at: 1.minute.from_now, payload: payload }.merge(attributes))
  end

  def with_runners_key(value)
    before = Settings.encryption[:runners_key]
    Settings.encryption[:runners_key] = value
    yield
  ensure
    Settings.encryption[:runners_key] = before
  end
end
