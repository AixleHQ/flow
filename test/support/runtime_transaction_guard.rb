# frozen_string_literal: true

# A runtime call is external I/O, and it is never made inside a database
# transaction, on any runtime (ContainerRuntime::BaseRuntime, "Transactions").
# This fails a test whose code makes one inside an application transaction.
#
# The test's own wrapping transaction (use_transactional_tests) is opened
# non-joinable, so it does not count. A transaction the code opens inside it is
# a joinable savepoint, and a test without the wrapper sees the code's real
# transaction, joinable too: both count.
#
# Every ContainerRuntime::BaseRuntime subclass is checked, ContainerRuntime::FakeRuntime
# included. A violation is recorded rather than raised, because the code under
# test may rescue what a runtime call raises, and the test fails at its teardown.
#
# Only calls on real runtime objects are checked. A Mocha double is not: a
# `mock("runtime")` is no BaseRuntime, and `runtime.stubs(:write_file)` puts
# the stub on the object's singleton class, in front of the check. A path
# tested only on doubles gets no check from here, so the main session-scoped
# callers each have a test on FakeRuntime or on RunnerRuntime with
# ContainerRuntime::FakeHostRunner: SessionContextService's assembly,
# Agents::CredentialDelivery, Sessions::AuthPause#heal! and
# Sessions::SecretRegistry.publish!.
module RuntimeTransactionGuard
  # Public methods of the runtime interface that make no external I/O, with
  # the reason. Every other one is checked.
  EXEMPT = {
    container_identifier: "reads the identifier off a handle it is given",
    session_identity: "names the session's object from the session row"
  }.freeze

  # The public methods ContainerRuntime::BaseRuntime itself declares: each
  # reaches a container, a cluster, a registry or a runner. Taken from
  # BaseRuntime, so a method declared there is checked without a change here.
  # A public method only a runtime subclass defines is not checked: declare a
  # runtime method on BaseRuntime for the guard to cover it.
  CALLS = (ContainerRuntime::BaseRuntime.public_instance_methods(false) - EXEMPT.keys).sort.freeze

  @violations = []
  @mutex = Mutex.new

  class << self
    def check!(runtime, call)
      connection = ActiveRecord::Base.connection_pool.active_connection
      return unless connection&.transaction_open? && connection.current_transaction.joinable?

      where = caller_locations(2, 6).map(&:to_s).join("\n    ")
      @mutex.synchronize { @violations << "#{runtime.class.name}##{call} inside a database transaction, from:\n    #{where}" }
    end

    def take
      @mutex.synchronize { @violations.dup.tap { @violations.clear } }
    end
  end

  # Prepended to every runtime class.
  module Calls
    CALLS.each do |call|
      define_method(call) do |*args, **kwargs, &block|
        RuntimeTransactionGuard.check!(self, call)
        super(*args, **kwargs, &block)
      end
    end
  end

  # Prepends Calls to a runtime class defined after this file was loaded.
  module Inherited
    def inherited(subclass)
      super
      subclass.prepend(Calls)
    end
  end

  module TestHooks
    extend ActiveSupport::Concern

    included do
      setup { RuntimeTransactionGuard.take }

      teardown do
        violations = RuntimeTransactionGuard.take
        flunk("A runtime call was made inside a database transaction (ContainerRuntime::BaseRuntime):\n" \
              "#{violations.uniq.join("\n")}") if violations.any?
      end
    end
  end
end

ContainerRuntime::BaseRuntime.singleton_class.prepend(RuntimeTransactionGuard::Inherited)
ContainerRuntime::BaseRuntime.descendants.each { |runtime| runtime.prepend(RuntimeTransactionGuard::Calls) }
ActiveSupport::TestCase.include(RuntimeTransactionGuard::TestHooks)
