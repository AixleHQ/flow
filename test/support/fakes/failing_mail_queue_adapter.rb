# frozen_string_literal: true

# A queue that refuses mail the way Solid Queue refuses a job when its database
# write fails: by raising SolidQueue::Job::EnqueueError. Every other job is
# queued as the test adapter queues it. A test class opts in with
#
#   def queue_adapter_for_test = FailingMailQueueAdapter.new
class FailingMailQueueAdapter < ActiveJob::QueueAdapters::TestAdapter
  def enqueue(job)
    refuse_mail(job)
    super
  end

  def enqueue_at(job, timestamp)
    refuse_mail(job)
    super
  end

  private

  def refuse_mail(job)
    return unless job.is_a?(ActionMailer::MailDeliveryJob)

    raise SolidQueue::Job::EnqueueError, "ActiveRecord::ConnectionNotEstablished: the queue database is unavailable"
  end
end
