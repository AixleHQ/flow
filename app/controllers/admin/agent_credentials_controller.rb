# frozen_string_literal: true

module Admin
  class AgentCredentialsController < Admin::ApplicationController
    # Prevent editing encrypted_config_data via admin
    def resource_params
      params.require(:agent_credential).permit(:user_id, :agent_type, :expires_at)
    end
  end
end
