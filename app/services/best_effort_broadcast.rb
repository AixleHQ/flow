# frozen_string_literal: true

# A broadcast on Action Cable's pub/sub (Redis) whose loss the caller can live
# with: a failed publish is logged and swallowed, never raised. Use it where a
# later read recovers what the message would have told (a poll that reads its
# queue again, a reconcile pass), as Runners::Operations and Runners::RelaySignals
# do. Deferring the publish until the surrounding transaction has committed
# stays the caller's call (`ActiveRecord.after_all_transactions_commit`).
#
#   BestEffortBroadcast.call("runner_env_7", context: "wake-up of runner_env_7") { { type: "wake_up" } }
module BestEffortBroadcast
  module_function

  # Publishes the block's Hash as JSON on `channel`. The block runs inside the
  # rescue, so a message that cannot be built is swallowed the same way. `context`
  # names what failed in the log line, which reads "<context> failed: <error>".
  def call(channel, context:)
    ActionCable.server.pubsub.broadcast(channel, yield.to_json)
  rescue StandardError => e
    Rails.logger.warn("#{context} failed: #{e.class}: #{e.message}")
  end
end
