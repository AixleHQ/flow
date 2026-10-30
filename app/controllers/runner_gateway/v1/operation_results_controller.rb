# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/ops/:id/result` (docs/design/agent-runtimes/DESIGN.md
    # §6.2, §6.4): the runner's outcome of one of its environment's ops.
    #
    # Body: {status: ok|error|expired, exit_code?, stdout?, stderr?, data?,
    # error?: {class, message}}. `ok` completes the op, `error` fails it, and
    # `expired` (the runner got it after its deadline_at and did not run it)
    # expires it. Idempotent on the op id: the first result wins, and a repeat
    # answers 200 and changes nothing.
    class OperationResultsController < ApplicationController
      before_action { authenticate(:access) }

      def create
        operation = RunnerOperation.find_by(id: params[:id], runner_environment_id: @credential.runner_environment_id)
        return refuse(:not_found, "not_found", "This environment has no such op.") if operation.nil?

        body = request.request_parameters
        result = outcome(body)
        if result.nil?
          return refuse(:unprocessable_entity, "invalid_result",
                        "`status` must be ok, error or expired, `exit_code` an integer, `stdout` and `stderr` " \
                        "strings, `data` an object and `error` an object of `class` and `message` strings.")
        end

        operation = Runners::Operations.record_result!(operation, status: body["status"], result: result)
        render json: { id: operation.id, state: operation.state }
      end

      private

      # What `result` stores: the body's known fields, or nil if one is not of
      # its type.
      def outcome(body)
        return nil unless Runners::Operations::RESULT_STATES.key?(body["status"])
        return nil unless body["exit_code"].nil? || body["exit_code"].is_a?(Integer)
        return nil unless %w[stdout stderr].all? { |key| body[key].nil? || body[key].is_a?(String) }
        return nil unless body["data"].nil? || body["data"].is_a?(Hash)
        return nil unless body["error"].nil? || error_object?(body["error"])

        body.slice("exit_code", "stdout", "stderr", "data", "error").to_h.compact
      end

      def error_object?(error)
        error.is_a?(Hash) && error.keys.all? { |key| %w[class message].include?(key) } &&
          error.values.all?(String)
      end
    end
  end
end
