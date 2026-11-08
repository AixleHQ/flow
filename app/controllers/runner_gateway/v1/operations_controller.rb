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
    #
    # The parameters are checked against
    # runner/protocol/schemas/v1/ops.query.json, whose `after` is at most
    # 2^63 - 1: runner_operations.sequence is a bigint, so a larger one cannot
    # be bound to the query.
    class OperationsController < ApplicationController
      before_action { authenticate(:access) }

      def index
        query = request.query_parameters.slice("after", "wait").transform_values { |value| decimal(value) }
        unless Runners::ProtocolSchema.valid?("ops.query", query)
          return refuse(:bad_request, "invalid_request",
                        "`after` and `wait` must be non-negative integers, and `after` at most 9223372036854775807.")
        end

        after = query.fetch("after", 0)
        wait = query.fetch("wait", Runners::Operations::MAX_WAIT)

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

      # A query parameter written as a base-10 integer, as that integer; any
      # other value as it came, for the schema to refuse.
      def decimal(value)
        (Integer(value, 10, exception: false) if value.is_a?(String)) || value
      end
    end
  end
end
