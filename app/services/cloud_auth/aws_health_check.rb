# frozen_string_literal: true

module CloudAuth
  # End-to-end check of a user's cloud connection: vend credentials the same way a
  # session would, then try to invoke a model with them.
  #
  # This is the platform equivalent of the `check` command in the corporate runbook,
  # which exists for exactly one reason — "Claude молчит об ошибке". Every layer that can
  # fail (refresh token, permission set, model enablement, region) fails differently
  # here, and the user sees which.
  class AwsHealthCheck
    # Probed when the connection pins nothing. Sonnet rather than Haiku deliberately:
    # Haiku is frequently not enabled in an account, so a Haiku failure would be a false
    # alarm. This matches what Claude Code itself falls back to on Bedrock.
    DEFAULT_PROBE_MODEL = "us.anthropic.claude-sonnet-4-6"

    Result = Data.define(:ok, :stage, :model_id, :error_code, :error_message) do
      def ok? = ok
    end

    def initialize(user:, vendor: nil, probe_factory: nil)
      @user = user
      @vendor = vendor
      @probe_factory = probe_factory
    end

    def call
      credential = @user.agent_credentials.find_by(agent_type: "claude_code")
      block = credential && credential.config_data[Agents::ClaudeCodeAdapter::BEDROCK_KEY]
      return failure(:not_connected, nil, "not_connected", "No AWS connection on this profile.") unless block.is_a?(Hash)

      vended = vend
      probe = build_probe(block, vended)
      result = probe.probe(model_id: probe_model(block))

      if result.ok?
        Result.new(ok: true, stage: :ok, model_id: result.model_id, error_code: nil, error_message: nil)
      else
        failure(:invoke, result.model_id, result.error_code, result.error_message)
      end
    rescue CloudAuth::Error => e
      # Credential vending never got as far as Bedrock. Reported as its own stage so the
      # UI can say "reconnect" rather than "check your model access".
      failure(:credentials, nil, e.class.name.demodulize.underscore, e.message)
    end

    private

    def vend
      (@vendor || AwsCredentialVendor.new(user: @user)).call
    end

    def build_probe(block, vended)
      args = {
        region: block["region"],
        access_key_id: vended.access_key_id,
        secret_access_key: vended.secret_access_key,
        session_token: vended.session_token
      }
      @probe_factory ? @probe_factory.call(**args) : AwsBedrockProbe.new(**args)
    end

    def probe_model(block)
      (block["models"] || {})["sonnet"].presence || DEFAULT_PROBE_MODEL
    end

    def failure(stage, model_id, code, message)
      Result.new(ok: false, stage: stage, model_id: model_id, error_code: code, error_message: message)
    end
  end
end
