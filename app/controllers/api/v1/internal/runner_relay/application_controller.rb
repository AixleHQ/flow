# frozen_string_literal: true

module Api
  module V1
    module Internal
      module RunnerRelay
        # The short calls the `runner-relay` service makes to the platform
        # (docs/design/agent-runtimes/runner-relay.md §8.2). Each answers in
        # milliseconds and holds no connection. They are authenticated by the
        # relay's internal token (`Settings.runners.relay.internal_token`), sent as
        # `Authorization: Bearer <token>` and compared in constant time. A platform
        # with no token set refuses every call.
        class ApplicationController < Api::V1::Internal::ApplicationController
          before_action :authenticate_relay!

          private

          def authenticate_relay!
            return if relay_token?

            head :unauthorized
          end

          # Both sides are digested first, so the comparison takes the same time
          # whatever the lengths, and a blank token matches nothing.
          def relay_token?
            expected = Settings.runners.relay.internal_token.to_s
            given = request.authorization.to_s[/\ABearer (\S+)\z/, 1].to_s
            return false if expected.blank? || given.blank?

            ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(given), Digest::SHA256.hexdigest(expected))
          end
        end
      end
    end
  end
end
