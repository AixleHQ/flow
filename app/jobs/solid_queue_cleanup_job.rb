# frozen_string_literal: true

# Solid Queue keeps every finished job (SolidQueue.preserve_finished_jobs) and
# deletes none of them unless something calls clear_finished_in_batches. Every
# model broadcast is a job, so without this the queue tables grow without bound.
#
# Scheduled in config/recurring.yml rather than as a Temporal schedule: it is the
# queue's own housekeeping, and it has to keep running while the Temporal worker
# is down — which is when the queue is the part still working.
class SolidQueueCleanupJob < ApplicationJob
  queue_as :default

  def perform
    SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)
  end
end
