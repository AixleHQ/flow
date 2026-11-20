# frozen_string_literal: true

module Api
  module V1
    module Internal
      module RunnerRelay
        # `POST /api/v1/internal/runner_relay/checks`: the relay's reconcile pass
        # (runner-relay.md §8.2, §8.3). Body `{"machines": [{"environment_id": 7,
        # "session_id": 123}]}`, answer `{"machines": [true]}` in the same order.
        # Runners::RelayChecks decides what valid means.
        class ChecksController < RunnerRelay::ApplicationController
          def create
            machines = machines_param
            return render json: { error: "machines must be a list of {environment_id, session_id}" }, status: :unprocessable_entity if machines.nil?

            render json: { machines: Runners::RelayChecks.valid(machines) }
          end

          private

          # The questions as plain hashes with integer ids, or nil when the body is
          # not a list of objects that carry both.
          def machines_param
            list = params[:machines]
            return unless list.is_a?(Array)

            list.map do |entry|
              return nil unless entry.respond_to?(:to_unsafe_h)

              hash = entry.to_unsafe_h
              environment_id, session_id = hash.values_at("environment_id", "session_id")
              return nil unless environment_id.is_a?(Integer)

              { "environment_id" => environment_id, "session_id" => (session_id if session_id.is_a?(Integer)) }
            end
          end
        end
      end
    end
  end
end
