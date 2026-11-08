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
module RuntimeTransactionGuard
  # The calls that reach a container, a cluster or a runner.
  CALLS = %i[
    pull_image create_container start_container wait_for_ready stop_container remove_container remove_image
    exec exec! write_file read_file
    container_status container_termination wait_container container_logs
    session_absent? cleanup_ready? cleanup_session
    list_session_resources delete_session_resource
  ].freeze

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
