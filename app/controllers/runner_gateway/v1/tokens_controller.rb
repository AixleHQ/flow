# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/token` (docs/design/agent-runtimes/DESIGN.md §6.2, §9.2):
    # the refresh token, sent as the bearer, is exchanged for a new pair of the
    # same family. Reusing a spent one revokes the family.
    class TokensController < ApplicationController
      before_action { authenticate(:refresh) }

      def create
        pair = Runners::Credentials.rotate!(@credential)
        record_heartbeat
        render_pair(pair)
      end
    end
  end
end
