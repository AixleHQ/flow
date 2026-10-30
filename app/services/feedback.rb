# frozen_string_literal: true

# Where the Send feedback dialog delivers to. The operator turns each destination
# on with its settings (`feedback` in config/settings.yml); with none configured
# the dialog is not offered at all.
module Feedback
  # Worth another attempt: the destination was unreachable or busy.
  class DeliveryFailed < StandardError; end

  # Never worth another attempt: the destination refused it, or is misconfigured.
  class DeliveryRejected < StandardError; end

  module_function

  def destinations
    { "slack" => SlackDestination, "board" => BoardDestination }
  end

  def configured
    destinations.select { |_name, destination| destination.configured? }
  end

  def enabled? = configured.any?

  def deliver_later(submission)
    configured.each_key { |name| DeliverJob.perform_later(submission, name) }
  end
end
