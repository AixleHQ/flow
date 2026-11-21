# frozen_string_literal: true

module Api
  module V1
    module Internal
      module RunnerRelay
        # `GET /api/v1/internal/runner_relay/holders/:route_token`: which machine holds
        # the runner session that has this route token, for the relay's registry
        # on a miss (runner-relay.md §7.1, §8.2). `404` when no runner session has
        # the token: a hosted session's token included. `environment_id` is the
        # machine that holds the session now (runner_environments.current_session_id),
        # null when none does.
        class HoldersController < RunnerRelay::ApplicationController
          def show
            session = TerminalSession.on_runner.find_by(route_token: params[:route_token].to_s)
            return head :not_found if session.nil?

            holder = Runners::Machines.held_by(session)
            render json: Runners::RelayRoute.describe(session, environment_id: holder&.id).except(:route_token)
          end
        end
      end
    end
  end
end
