# frozen_string_literal: true

require "test_helper"

# config/recurring.yml is read by the Solid Queue supervisor in deployed
# environments and by nothing else — so a typo in a class name, or an entry that
# quietly stops being scheduled, is invisible until the thing it schedules is
# needed. Which, for a watchdog, is the worst possible moment to find out.
class RecurringTasksTest < ActiveSupport::TestCase
  CONFIG = Rails.application.config_for(:recurring, env: "production").freeze

  test "every recurring task names a real job class" do
    assert CONFIG.any?, "config/recurring.yml has no production entries"

    CONFIG.each do |name, task|
      klass = task[:class].to_s.safe_constantize
      assert klass, "recurring task #{name} names #{task[:class].inspect}, which does not exist"
      assert_operator klass, :<, ActiveJob::Base,
        "recurring task #{name} names #{klass}, which is not an ActiveJob"
      assert task[:schedule].present?, "recurring task #{name} has no schedule"
    end
  end

  # The entries this file exists for. Every other recurring job in the app is a
  # Temporal schedule executed by the worker; these two must not be. One watches
  # the worker, so it cannot be hosted by it. The other resizes the queue, and a
  # queue that cannot be resized while the worker is down is a queue nobody can
  # rescue. If either migrates to app/temporal/schedules.yml, that is lost.
  {
    queue_health_check: "QueueHealthCheckJob",
    session_admission_sync: "SessionAdmissionSyncJob"
  }.each do |name, klass|
    test "#{name} is scheduled outside Temporal in every deployed environment" do
      %w[production staging].each do |env|
        task = Rails.application.config_for(:recurring, env: env)[name]

        assert task, "#{env} does not schedule #{name} outside Temporal"
        assert_equal klass, task[:class]
      end

      schedules = File.read(Rails.root.join("app/temporal/schedules.yml"))
      assert_not schedules.include?(name.to_s),
        "#{name} must not be a Temporal schedule — it has to survive the worker"
    end
  end
end
