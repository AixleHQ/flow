# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/ops/:id/result` (docs/design/agent-runtimes/DESIGN.md
    # §6.2, §6.4): the runner's outcome of one of its environment's ops.
    #
    # Body: {status: ok|error|expired, exit_code?, stdout?, stderr?, data?,
    # error?: {class, message}}, which Runners::Operations.record_result!
    # checks and stores, refusing one that fails its schema with
    # `invalid_result`. `ok` completes the op, `error` fails it, and `expired`
    # (the runner got it after its deadline_at and did not run it) expires it.
    # Idempotent on the op id: the first result wins, and a repeat answers 200
    # and changes nothing.
    class OperationResultsController < ApplicationController
      before_action { authenticate(:access) }

      def create
        operation = RunnerOperation.find_by(id: params[:id], runner_environment_id: @credential.runner_environment_id)
        return refuse(:not_found, "not_found", "This environment has no such op.") if operation.nil?

        operation = Runners::Operations.record_result!(operation, request.request_parameters)
        render json: { id: operation.id, state: operation.state }
      end
    end
  end
end
