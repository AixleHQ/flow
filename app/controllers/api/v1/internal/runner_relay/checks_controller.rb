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
          # not a list of objects that carry both. The permitted params define the
          # shape (a scalar `environment_id` and `session_id` in each object, nothing
          # else); the Integer check defines the types, as a permitted scalar still
          # lets `"123"` through: a `session_id` is an Integer, or absent or null.
          def machines_param
            list = params[:machines]
            return unless list.is_a?(Array)
            return [] if list.empty?

            entries = params.expect(machines: [ [ :environment_id, :session_id ] ])
            # An element that is not an object is dropped by the permit: the answers
            # would no longer line up with the questions.
            return unless entries.size == list.size

            questions = entries.map { |entry| question(entry) }
            questions if questions.all?
          rescue ActionController::ParameterMissing
            nil
          end

          def question(entry)
            environment_id, session_id = entry.to_h.values_at("environment_id", "session_id")
            return unless environment_id.is_a?(Integer) && (session_id.nil? || session_id.is_a?(Integer))

            { "environment_id" => environment_id, "session_id" => session_id }
          end
        end
      end
    end
  end
end
