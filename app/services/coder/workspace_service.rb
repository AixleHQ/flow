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

    # Coder refused a request because the account is out of quota. A kind of
    # `OperationError`, so a caller that does not care keeps rescuing that.
    class QuotaError < OperationError; end

    # Operator-tunable from `settings.yml` (`Settings.coder.await_build_timeout`,
    # `CODER_AWAIT_BUILD_TIMEOUT`). The numeric fallback matches DD-14 / OQ-6.
    DEFAULT_BUILD_TIMEOUT  = (Settings.coder&.await_build_timeout || 240).to_i
    DEFAULT_BUILD_INTERVAL = 3   # seconds
    EXPLANATION_LIMIT      = 300
    GONE_STATUSES          = [ 404, 410 ].freeze

    # What Coder answers when the account is out of quota. The exact status and
    # body of a refusal are recorded on staging (design runner-coder.md §15);
    # until then a refusal is a quota one only when it says so itself.
    QUOTA_STATUSES = [ 402, 403, 409, 429 ].freeze

    def initialize(integration)
      @integration = integration
      @token       = Coder::TokenService.new(integration)
    end

    # `own: true` lists only workspaces the integration's token owns — never the
    # personal workspaces an admin token can also see. `prefix:` keeps the pool's
    # workspaces, matched by Coder::Pool and not by the start of the name.
    def list(prefix: nil, own: false)
      workspaces = Coder::Api.list_workspaces(coder_url: coder_url, session_token: session_token,
                                              query: own ? "owner:me" : nil)
      workspaces = workspaces.select { |w| Coder::Pool.matches?(prefix, w["name"]) } if prefix.present?
      workspaces
    rescue Coder::Api::ApiError => e
      raise OperationError, "list workspaces failed: #{@token.redact(e.message)}"
    end

    def find_by_name(name)
      list.find { |w| w["name"].to_s == name.to_s }
    end

    # One `GET`: the status of one of the token owner's workspaces. A workspace
    # Coder does not know (404) or has deleted (410) is `deleted`.
    def status(name)
      workspace = Coder::Api.get_workspace_by_name(coder_url: coder_url, session_token: session_token, name: name)
      Coder::WorkspaceStatus.from(workspace)
    rescue Coder::Api::HTTPError => e
      return Coder::WorkspaceStatus.from(nil) if GONE_STATUSES.include?(e.status)

      raise OperationError, "workspace status failed: #{@token.redact(e.message)}"
    rescue Coder::Api::ApiError => e
      raise OperationError, "workspace status failed: #{@token.redact(e.message)}"
    end

    # Starts a stopped workspace without waiting for the build. Returns the
    # build to wait for: the start build already in flight, or the one just
    # started. Returns nil when the workspace is already running.
    #
    # A start already in flight is reused, not repeated: another `start` against
    # the same workspace would race it and answer HTTP 409.
    # `status` defaults to the one read off `workspace`; a caller that holds
    # only the workspace's id passes the status it fetched.
    def ensure_started_async(workspace, status: Coder::WorkspaceStatus.from(workspace))
      return nil if status.running?
      return { "id" => status.build_id } if status.building? && status.transition == "start" && status.build_id

      start(workspace["id"])
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
      raise QuotaError, "build (#{transition}) failed: #{with_coder_explanation(e)}" if quota_refusal?(e)

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
        raise OperationError, build_failure(build_id, build) if %w[failed canceled].include?(status)
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
      raise QuotaError, "create_workspace failed: #{with_coder_explanation(e)}" if quota_refusal?(e)

      raise OperationError, "create_workspace failed: #{with_coder_explanation(e)}"
    end

    private

    # Coder refuses a request with `{"message": ..., "detail": ...}`; the status
    # alone does not tell a missing template parameter from an exhausted quota.
    def with_coder_explanation(error)
      plain = @token.redact(error.message)
      return plain unless error.is_a?(Coder::Api::HTTPError)

      body = JSON.parse(error.body.to_s)
      return plain unless body.is_a?(Hash)

      message, detail = body.values_at("message", "detail").map { |part| part.to_s.strip }
      explanation = [ message, ("(#{detail})" if detail.present?) ].compact_blank.join(" ")
      explanation.empty? ? plain : "#{plain} — #{redacted_excerpt(explanation)}"
    rescue JSON::ParserError
      plain
    end

    def quota_refusal?(error)
      return false unless error.is_a?(Coder::Api::HTTPError) && QUOTA_STATUSES.include?(error.status)

      body = JSON.parse(error.body.to_s)
      body.is_a?(Hash) && body.values_at("message", "detail").any? { |part| part.to_s.match?(/quota/i) }
    rescue JSON::ParserError
      false
    end

    def build_failure(build_id, build)
      message = "build #{build_id} failed: status=#{build.dig('job', 'status')}"
      error   = build.dig("job", "error").to_s.strip
      error.empty? ? message : "#{message} — #{redacted_excerpt(error)}"
    end

    # Redact before truncating: a cut through the token would leave a fragment
    # the redaction no longer matches.
    def redacted_excerpt(text)
      @token.redact(text).truncate(EXPLANATION_LIMIT)
    end

    def coder_url
      @token.coder_url
    end

    def session_token
      @token.session_token
    end
  end
end
