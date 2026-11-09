# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/ops/:id/result` (docs/design/agent-runtimes/DESIGN.md
    # §6.2, §6.4): the runner's outcome of one of its environment's ops.
    #
    # Body: {status: ok|error|expired, exit_code?, stdout?, stderr?, data?,
    # error?: {class, message}}, checked against
    # runner/protocol/schemas/v1/op_result.request.json. `ok` completes the op,
    # `error` fails it, and `expired` (the runner got it after its deadline_at
    # and did not run it) expires it. Idempotent on the op id: the first result
    # wins, and a repeat answers 200 and changes nothing.
    class OperationResultsController < ApplicationController
      before_action { authenticate(:access) }

      def create
        operation = RunnerOperation.find_by(id: params[:id], runner_environment_id: @credential.runner_environment_id)
        return refuse(:not_found, "not_found", "This environment has no such op.") if operation.nil?

        body = request.request_parameters
        unless Runners::ProtocolSchema.valid?("op_result.request", body)
          return refuse(:unprocessable_entity, "invalid_result",
                        "`status` must be ok, error or expired, `exit_code` an integer, `stdout` and `stderr` " \
                        "strings, `data` an object and `error` an object of `class` and `message` strings.")
        end

        operation = Runners::Operations.record_result!(operation, status: body["status"], result: outcome(body))
        render json: { id: operation.id, state: operation.state }
      end

      private

      # What `result` stores: the body's known fields, a `null` one left out.
      # JSON Schema counts 1.0 as an integer, so `exit_code` is stored as one.
      def outcome(body)
        result = body.slice("exit_code", "stdout", "stderr", "data", "error").to_h.compact
        result["exit_code"] = result["exit_code"].to_i if result.key?("exit_code")
        result
      end
    end
  end
end
