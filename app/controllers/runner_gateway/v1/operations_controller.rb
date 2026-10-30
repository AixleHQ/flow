# frozen_string_literal: true

module RunnerGateway
  module V1
    # `GET /runner/v1/ops?after=<seq>&wait=<s>` (docs/design/agent-runtimes/DESIGN.md
    # §6.2, §6.7): the long-poll a runner takes its environment's ops from.
    # `after` is the runner's acknowledgement, so ops at or below it are not
    # returned again. With nothing to return the request waits up to `wait`
    # seconds (default and maximum 25) and answers the moment an op is
    # enqueued; an empty 200 after the wait is the heartbeat.
    class OperationsController < ApplicationController
      before_action { authenticate(:access) }

      def index
        after = non_negative_integer(params[:after], default: 0)
        wait = non_negative_integer(params[:wait], default: Runners::Operations::MAX_WAIT)
        if after.nil? || wait.nil?
          return refuse(:bad_request, "invalid_request", "`after` and `wait` must be non-negative integers.")
        end

        operations = Runners::Operations.poll(@credential.runner_environment, after: after, wait: wait)
        response.set_header("Cache-Control", "no-store")
        render json: { ops: operations.map { |operation| RunnerGatewayOperationResource.new(operation).to_h } }
      end

      private

      def non_negative_integer(value, default:)
        return default if value.nil?

        integer = Integer(value, 10, exception: false) if value.is_a?(String)
        integer if integer && integer >= 0
      end
    end
  end
end
