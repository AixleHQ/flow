# frozen_string_literal: true

module Admin
  class AgentModelsController < Admin::ApplicationController
    def index
      @runtimes = User::AVAILABLE_AGENTS
      @selected_runtime = params[:agent_runtime] || @runtimes.first
      @user = params[:user_id].present? ? User.find(params[:user_id]) : current_user

      credential = @user.agent_credentials.find_by(agent_type: @selected_runtime)
      @models = if credential
        # Use separate cache key to avoid poisoning user cache
        cache_key = "admin_agent_models:#{@user.id}:#{@selected_runtime}"
        Rails.cache.fetch(cache_key, expires_in: 1.hour) do
          AgentCredentialsService.for(@selected_runtime).adapter.fetch_available_models(credential.config_data)
        end
      else
        []
      end
      @credential_present = credential.present?
    end
  end
end
