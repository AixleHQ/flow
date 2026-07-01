# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Base controller for service-to-service (non-user) API endpoints.
      #
      # These endpoints authenticate by other means (raw-body service tokens,
      # Traefik ForwardAuth session forwarding) and do their own authorization
      # inline. They must therefore be excluded from the user-facing Pundit
      # machinery enabled on Api::V1::ApplicationController.
      class ApplicationController < Api::V1::ApplicationController
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :dynamic_authorize!, raise: false
        skip_before_action :deny_read_only_mutation!, raise: false
        skip_after_action :verify_authorized, raise: false
      end
    end
  end
end
