# frozen_string_literal: true

class Api::V1::AgentModelsController < Api::V1::ApplicationController
  # @tags AgentModels
  # @summary List available models for an agent runtime
  #
  # @query_parameter agent_runtime(required) [String] Agent runtime (claude_code, codex, gemini_cli, cursor_cli)
  # @response Success(200) [Array<Hash>]
  def index
    agent_runtime = params[:agent_runtime]
    unless User::AVAILABLE_AGENTS.include?(agent_runtime)
      return render json: { error: "Invalid agent_runtime. Must be one of: #{User::AVAILABLE_AGENTS.join(', ')}" }, status: :bad_request
    end

    credential = current_user.agent_credentials.find_by(agent_type: agent_runtime)
    unless credential
      return render json: { error: "No credential configured for #{agent_runtime}. Complete agent setup first." }, status: :not_found
    end

    models = AgentCredentialsService.for(agent_runtime).adapter.fetch_available_models(credential.config_data)

    render json: models
  rescue StandardError => e
    Rails.logger.error("[AgentModelsController#index] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render json: { error: "Failed to fetch models from provider" }, status: :bad_gateway
  end

  # @tags AgentModels
  # @summary Set default model for an agent credential
  #
  # @request_body [Hash{ agent_credential_id: Integer, default_model: String }]
  # @response Success(200) [User]
  def update_default
    credential = current_user.agent_credentials.find(params[:agent_credential_id])
    model = params[:default_model]

    if model.present? && !model.match?(/\A[a-z0-9][a-z0-9._:-]*\z/)
      return render json: { error: "Invalid model ID format" }, status: :unprocessable_entity
    end

    meta = credential.metadata || {}
    if model.present?
      meta["default_model"] = model
    else
      meta.delete("default_model")
    end
    credential.update!(metadata: meta)

    respond_with current_user, serializer: CurrentUserSerializer
  end
end
