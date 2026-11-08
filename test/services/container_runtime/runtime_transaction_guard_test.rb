# frozen_string_literal: true

require "test_helper"

# test/support/runtime_transaction_guard.rb: a runtime call inside an
# application transaction is recorded, and the test's own wrapping transaction
# does not count.
class RuntimeTransactionGuardTest < ActiveSupport::TestCase
  setup { @runtime = ContainerRuntime::FakeRuntime.new }

  test "a runtime call outside an application transaction is not a violation" do
    @runtime.container_status("ctr")

    assert_empty RuntimeTransactionGuard.take
  end

  test "a runtime call inside an application transaction is a violation" do
    ActiveRecord::Base.transaction { @runtime.write_file("ctr", "/tmp/x", "y") }
    ActiveRecord::Base.transaction(requires_new: true) { @runtime.exec("ctr", [ "true" ]) }

    violations = RuntimeTransactionGuard.take
    assert(violations.any? { |v| v.start_with?("ContainerRuntime::FakeRuntime#write_file inside a database transaction") }, violations.inspect)
    assert(violations.any? { |v| v.start_with?("ContainerRuntime::FakeRuntime#exec inside a database transaction") }, violations.inspect)
  end

  test "every runtime class is guarded" do
    [ ContainerRuntime::DockerRuntime, ContainerRuntime::KubernetesRuntime, ContainerRuntime::RunnerRuntime,
      ContainerRuntime::FakeRuntime ].each do |runtime|
      assert_includes runtime.ancestors, RuntimeTransactionGuard::Calls, runtime.name
    end
  end
end
