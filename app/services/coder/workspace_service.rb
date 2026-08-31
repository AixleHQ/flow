# frozen_string_literal: true

module Coder
  # WorkspaceService — workspace-level orchestration for a Coder integration.
  #
  # The service owns integration-level concerns (credentials, prefix filtering,
  # await-build polling, template lookup) and delegates every API call to
  # `Coder::Api`. Transport details (Faraday client, endpoint paths, JSON
  # parsing) live in `Coder::Api`; this layer raises a single domain-level
  # `OperationError` for the caller.
  class WorkspaceService
    class OperationError < StandardError; end

    # Operator-tunable from `settings.yml` (`Settings.coder.await_build_timeout`,
    # `CODER_AWAIT_BUILD_TIMEOUT`). The numeric fallback matches DD-14 / OQ-6.
    DEFAULT_BUILD_TIMEOUT  = (Settings.coder&.await_build_timeout || 240).to_i
    DEFAULT_BUILD_INTERVAL = 3   # seconds

    def initialize(integration)
      @integration = integration
      @token       = Coder::TokenService.new(integration)
    end

    def list(prefix: nil)
      workspaces = Coder::Api.list_workspaces(coder_url: coder_url, session_token: session_token)
      workspaces = workspaces.select { |w| w["name"].to_s.start_with?(prefix) } if prefix.present?
      workspaces
    rescue Coder::Api::ApiError => e
      raise OperationError, "list workspaces failed: #{@token.redact(e.message)}"
    end

    def find_by_name(name)
      list.find { |w| w["name"].to_s == name.to_s }
    end

    def start(workspace_id)
      build(workspace_id, transition: "start")
    end

    def stop(workspace_id)
      build(workspace_id, transition: "stop")
    end

    # Destroys the workspace and its cloud resources. Coder models deletion as
    # a build transition like start/stop, not as an HTTP DELETE, so the returned
    # build runs asynchronously — the workspace keeps being listed with
    # `transition: "delete"` until it finishes. Callers that need the terminal
    # state pass the build id to `await_build`.
    def delete(workspace_id, orphan: false)
      build(workspace_id, transition: "delete", orphan: orphan)
    end

    def build(workspace_id, transition:, orphan: false)
      Coder::Api.build_workspace(
        coder_url:     coder_url,
        session_token: session_token,
        workspace_id:  workspace_id,
        transition:    transition,
        orphan:        orphan
      )
    rescue Coder::Api::ApiError => e
      raise OperationError, "build (#{transition}) failed: #{@token.redact(e.message)}"
    end

    # Poll a workspace build until it reaches a terminal status or the
    # timeout fires. Returns the final build hash. Raises `OperationError`
    # on failure / timeout. The default 240s budget is documented in § 9.1.1
    # of the v4 design (DD-14 / OQ-6).
    def await_build(build_id, timeout: DEFAULT_BUILD_TIMEOUT, interval: DEFAULT_BUILD_INTERVAL)
      deadline = Time.current + timeout
      loop do
        build = Coder::Api.get_workspace_build(
          coder_url:     coder_url,
          session_token: session_token,
          build_id:      build_id
        )
        status = build.dig("job", "status").to_s
        return build if status == "succeeded"
        raise OperationError, "build #{build_id} failed: status=#{status}" if %w[failed canceled].include?(status)
        raise OperationError, "await_build timed out after #{timeout}s" if Time.current >= deadline

        sleep interval
      end
    rescue Coder::Api::ApiError => e
      raise OperationError, "await_build failed: #{@token.redact(e.message)}"
    end

    def find_template(template_name)
      templates = Coder::Api.list_templates(coder_url: coder_url, session_token: session_token)
      templates.find { |t| t["name"].to_s == template_name.to_s }
    end

    def create_workspace(name:, template_id: nil, template_name: nil)
      user_id = @integration.coder_user_id.to_s
      raise OperationError, "create_workspace: integration missing user_id" if user_id.empty?

      tpl_id = template_id || (template_name.present? ? find_template(template_name)&.dig("id") : nil)
      raise OperationError, "create_workspace: template not found (#{template_name})" if tpl_id.blank?

      Coder::Api.create_workspace(
        coder_url:     coder_url,
        session_token: session_token,
        user_id:       user_id,
        name:          name,
        template_id:   tpl_id
      )
    rescue Coder::Api::ApiError => e
      raise OperationError, "create_workspace failed: #{@token.redact(e.message)}"
    end

    private

    def coder_url
      @token.coder_url
    end

    def session_token
      @token.session_token
    end
  end
end
