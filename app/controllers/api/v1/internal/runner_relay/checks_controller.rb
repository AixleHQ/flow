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
          # not a list of objects that carry both: a `session_id` is an Integer, or
          # absent or null.
          def machines_param
            list = params[:machines]
            return unless list.is_a?(Array)

            questions = list.map { |entry| question(entry) }
            questions if questions.all?
          end

          def question(entry)
            return unless entry.respond_to?(:to_unsafe_h)

            environment_id, session_id = entry.to_unsafe_h.values_at("environment_id", "session_id")
            return unless environment_id.is_a?(Integer) && (session_id.nil? || session_id.is_a?(Integer))

            { "environment_id" => environment_id, "session_id" => session_id }
          end
        end
      end
    end
  end
end
