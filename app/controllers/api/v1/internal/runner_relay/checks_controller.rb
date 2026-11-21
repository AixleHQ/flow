# frozen_string_literal: true

module Api
  module V1
    module Internal
      module RunnerRelay
        # `POST /api/v1/internal/runner_relay/checks`: the relay's reconcile pass
        # (runner-relay.md §8.2, §8.3). Body `{"machines": [{"environment_id": 7,
        # "session_id": 123}]}`, answer `{"machines": [true]}` in the same order.
        # The body is checked against its schema (`checks.request`, runner-relay/schemas/);
        # Runners::RelayChecks decides what valid means.
        class ChecksController < RunnerRelay::ApplicationController
          def create
            body = request.request_parameters
            unless Runners::ProtocolSchema.valid?("checks.request", body)
              return render json: { error: "machines must be a list of {environment_id, session_id}" }, status: :unprocessable_entity
            end

            machines = body["machines"].map do |machine|
              { "environment_id" => machine["environment_id"].to_i, "session_id" => machine["session_id"]&.to_i }
            end
            render json: { machines: Runners::RelayChecks.valid(machines) }
          end
        end
      end
    end
  end
end
