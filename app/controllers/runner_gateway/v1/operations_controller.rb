# frozen_string_literal: true

module RunnerGateway
  module V1
    # `GET /runner/v1/ops?after=<seq>&wait=<s>` (docs/design/agent-runtimes/DESIGN.md
    # §6.2, §6.7): the long-poll a runner takes its environment's ops from.
    # `after` is the runner's acknowledgement, so ops at or below it are not
    # returned again. With nothing to return the request waits up to `wait`
    # seconds (default and maximum 25) and answers the moment an op is
    # enqueued; an empty 200 after the wait is the heartbeat.
    #
    # The access checks run again once the wait is over, before anything is
    # serialized: a credential revoked, an environment gone or the flag turned
    # off while the poll waited gets the refusal, not the payload. The ops the
    # poll selected stay deliverable until `after` acknowledges them, so
    # refusing then loses none.
    class OperationsController < ApplicationController
      # runner_operations.sequence is a bigint: a larger `after` cannot be
      # bound to the query.
      MAX_SEQUENCE = (2**63) - 1

      before_action { authenticate(:access) }

      def index
        after = non_negative_integer(params[:after], default: 0)
        wait = non_negative_integer(params[:wait], default: Runners::Operations::MAX_WAIT)
        if after.nil? || wait.nil? || after > MAX_SEQUENCE
          return refuse(:bad_request, "invalid_request",
                        "`after` and `wait` must be non-negative integers, and `after` at most #{MAX_SEQUENCE}.")
        end

        operations = Runners::Operations.poll(@credential.runner_environment, after: after, wait: wait)
        if wait.positive?
          reauthenticate
          return if performed?
        end

        response.set_header("Cache-Control", "no-store")
        render json: { ops: operations.map { |operation| RunnerGatewayOperationResource.new(operation).to_h } }
      end

      private

      # The before_action's checks, read fresh: this request's query cache, its
      # memoized flag values and the request-local copy of Rails.cache still
      # hold the answers from before the wait.
      def reauthenticate
        Current.feature_snapshot = nil
        Rails.cache.with_local_cache { ActiveRecord::Base.uncached { authenticate(:access) } }
      end

      def non_negative_integer(value, default:)
        return default if value.nil?

        integer = Integer(value, 10, exception: false) if value.is_a?(String)
        integer if integer && integer >= 0
      end
    end
  end
end
