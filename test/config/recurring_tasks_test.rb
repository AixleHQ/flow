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

  # The one entry this file exists for. Every other recurring job in the app is a
  # Temporal schedule executed by the worker; this one must not be, because the
  # worker is what it watches. If it ever migrates to app/temporal/schedules.yml,
  # the installation goes back to having no watchdog that survives a dead worker.
  test "the queue watchdog is scheduled outside Temporal in every deployed environment" do
    %w[production staging qa].each do |env|
      config = Rails.application.config_for(:recurring, env: env)
      task = config[:queue_health_check]

      assert task, "#{env} does not schedule queue_health_check outside Temporal"
      assert_equal "QueueHealthCheckJob", task[:class]
    end

    assert_not File.read(Rails.root.join("app/temporal/schedules.yml")).include?("queue_health"),
      "the queue watchdog must not be a Temporal schedule — the worker is what it watches"
  end
end
