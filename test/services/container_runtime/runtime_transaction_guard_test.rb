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

  # The guard's list is the runtime interface: a runtime method added to
  # ContainerRuntime::BaseRuntime is checked with no change to the guard, and
  # only a listed exemption, with its reason, is not.
  test "the guard checks every public method of the runtime interface but its listed exemptions" do
    interface = ContainerRuntime::BaseRuntime.public_instance_methods(false)

    assert_equal interface.sort, (RuntimeTransactionGuard::CALLS + RuntimeTransactionGuard::EXEMPT.keys).sort
    assert_empty RuntimeTransactionGuard::CALLS & RuntimeTransactionGuard::EXEMPT.keys
    assert(RuntimeTransactionGuard::EXEMPT.values.all?(&:present?), "every exemption says why")
    assert_equal RuntimeTransactionGuard::CALLS.sort, RuntimeTransactionGuard::Calls.instance_methods(false).sort
    %i[image_digest resolve_container cleanup_session session_absent? cleanup_ready?].each do |call|
      assert_includes RuntimeTransactionGuard::CALLS, call
    end
  end

  test "image_digest and resolve_container are checked" do
    ActiveRecord::Base.transaction do
      @runtime.image_digest("ghcr.io/aixlehq/flow-claude-code:latest")
      @runtime.resolve_container("ctr")
    end

    violations = RuntimeTransactionGuard.take
    assert(violations.any? { |v| v.start_with?("ContainerRuntime::FakeRuntime#image_digest inside a database transaction") }, violations.inspect)
    assert(violations.any? { |v| v.start_with?("ContainerRuntime::FakeRuntime#resolve_container inside a database transaction") }, violations.inspect)
  end

  test "every runtime class is guarded" do
    [ ContainerRuntime::DockerRuntime, ContainerRuntime::KubernetesRuntime, ContainerRuntime::RunnerRuntime,
      ContainerRuntime::FakeRuntime ].each do |runtime|
      assert_includes runtime.ancestors, RuntimeTransactionGuard::Calls, runtime.name
    end
  end
end
