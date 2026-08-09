# frozen_string_literal: true

class SessionService
  # Raised at session-start when a selected custom MCP server's URL fails a
  # safety re-check (F34): the URL is validated at create/update, but DNS or the
  # stored value may have changed since, so we re-check before dialing.
  class UnsafeMcpUrlError < StandardError; end

  class << self
    # `company:` is required for PROJECT-LESS sessions (auth_setup): those create
    # an agent credential, and the credential is billed to a company, so it can
    # never be guessed. Project-bound sessions take the project's company.
    def create_and_start(user:, project: nil, company: nil, session_type:, agent_type: nil, configured_agent: nil, params: {})
      # Session-start preflight (oauth-unification §4.6): block the launch with a
      # "Connect …" CTA when a selected OAuth MCP server has no usable credential for
      # this user, instead of starting a session that fails silently at provisioning.
      preflight_oauth!(user, params[:mcp_server_ids])
      preflight_cloud!(user, company || project&.company)
      preflight_url_safety!(params[:mcp_server_ids])

      # auth_kind ("design") is carried in metadata so AgentAuthStrategy can run the
      # /design-login variant (inject the base credential, watch designOauth.accessToken).
      metadata = (params[:metadata] || {}).to_h
      metadata["auth_kind"] = params[:auth_kind] if params[:auth_kind].present?

      session = user.terminal_sessions.build(
        project: project,
        company_id: company&.id || project&.company_id,
        session_type: session_type,
        agent_type: agent_type,
        configured_agent: configured_agent,
        metadata: metadata.presence,
        **params.slice(:mode, :initial_prompt, :requested_model, :session_config,
                       :tool_ids, :skill_ids, :mcp_server_ids, :input_asset_ids, :repository_ids)
      )

      return session unless session.save

      session.start! if session.may_start?
      start_temporal_workflow(session)

      session
    end

    def finish(session:)
      unless session.may_start_finishing? || session.finishing?
        raise TerminalSession::InvalidStateError, "Cannot finish session in state: #{session.state}"
      end

      return unless session.may_start_finishing?

      session.start_finishing!

      if session.temporal_workflow_id.present?
        signal_container_finished(session)
      else
        session.finish! if session.may_finish?
      end
    end

    def cancel(session:)
      cancel_temporal_workflow(session) if session.temporal_workflow_id.present?
      session.fail! if session.may_fail?
    end

    # Fail a session AND wake its container workflow, so the container's cleanup
    # phase actually runs. THE blessed way to fail a session from outside the
    # container workflow (watchdogs, scanners) — do not hand-roll
    # `update!(error_message:) + fail!`.
    #
    # Why the signal is not optional: `TerminalSession#on_failed` only notifies the
    # PARENT workflow run ("workflow-execution-<id>", via WorkflowService), which
    # completes the step. The session's own container workflow is a different
    # execution ("agent-session-<id>") and it is parked in its `exec` phase
    # awaiting `container_finished` with a 23-hour signal timeout (see
    # WorkflowStepStrategy#phase_config). Failing the row without signalling that
    # execution leaves it spinning until the timeout, and its cleanup phase — the
    # only thing that deletes the pod, Service, IngressRoute and Middlewares —
    # never runs. Every such failure leaked its Kubernetes objects for a day.
    #
    # Ordering mirrors `finish`: transition first, signal second. The cleanup phase
    # decides the step's outcome from `session.state` (CompleteStepActivity), so it
    # must already read `failed`. Clearing `container_id` in `on_failed` is safe —
    # the cleanup phase takes its container reference from the workflow's own
    # accumulated state, not from the row.
    def fail_session(session:, error_message: nil)
      session.update!(error_message: error_message) if error_message.present?
      session.fail! if session.may_fail?
      signal_container_finished(session) if session.temporal_workflow_id.present?
      session
    end

    def create_for_workflow_step(step_run:)
      workflow_run = step_run.workflow_run
      step = step_run.step

      prompt = step.instructions.presence || "Execute step: #{step.name}"
      runtime = step.required_agent_runtime.presence ||
                workflow_run.agent_runtime.presence ||
                run_membership(workflow_run)&.default_agent_runtime.presence ||
                run_credentials(workflow_run).order(created_at: :desc).first&.agent_type ||
                "claude_code"

      run_model = workflow_run.shared_context&.dig("requested_model")

      session = TerminalSession.create!(
        user: workflow_run.user,
        project: workflow_run.project,
        company_id: workflow_run.project&.company_id,
        session_type: "workflow_step",
        agent_type: runtime,
        configured_agent: step.agent,
        mode: "interactive",
        initial_prompt: prompt,
        requested_model: step.preferred_model.presence || run_model,
        metadata: {
          "workflow_run_id" => workflow_run.id,
          "step_run_id" => step_run.id,
          "step_name" => step.name
        }
      )

      step_run.update!(terminal_session: session)

      config = SessionConfigResolver.resolve(session)
      session.update!(agent_type: config[:agent_runtime], mode: config[:mode])
      attach_resolved_resources(session, config)
      session.start! if session.may_start?
      start_temporal_workflow(session)

      session
    end

    private

    # Workflow runs are project-bound, so the run's project names the company
    # whose credential (and whose bill) this step must use.
    def run_membership(workflow_run)
      CompanyMembership.find_by(user_id: workflow_run.user_id,
                                company_id: workflow_run.project&.company_id)
    end

    def run_credentials(workflow_run)
      company_id = workflow_run.project&.company_id
      return AgentCredential.none if company_id.blank?

      AgentCredential.where(user_id: workflow_run.user_id, company_id: company_id)
    end

    # Raises Oauth::PreflightError (rescued by the API controller) when any selected
    # OAuth MCP server lacks a usable credential for `user`. Interactive launches
    # only — workflow-step sessions (create_for_workflow_step) are automated and have
    # no interactive user to show a Connect CTA to.
    def preflight_oauth!(user, mcp_server_ids)
      return if mcp_server_ids.blank?

      servers = MCPServer.where(id: mcp_server_ids, enabled: true)
      missing = Oauth::Preflight.missing_connections(servers, user: user)
      raise Oauth::PreflightError, missing if missing.any?
    end

    # Raises CloudAuth::PreflightError when the cloud connection this session would use
    # is present but rotten. A credential source inside the container cannot talk to the
    # user, and Claude Code hides Bedrock errors — so without this the session would
    # launch and then simply not answer. No cloud connection at all is unaffected.
    #
    # `company` is the one the session will be billed to — the same resolution the
    # session itself gets from SessionCompany, done before the record exists.
    def preflight_cloud!(user, company)
      broken = CloudAuth::Preflight.broken_connections(user: user, company: company)
      raise CloudAuth::PreflightError, broken if broken.any?
    end

    # Re-validate selected custom MCP server URLs right before launch (F34). The
    # model validates at create/update, but DNS (rebinding) or the stored value
    # may have changed since — a host that now resolves to a private/internal IP
    # must not be dialed. Cheap: url_safety uses local resolvers only.
    def preflight_url_safety!(mcp_server_ids)
      return if mcp_server_ids.blank?

      unsafe = MCPServer.where(id: mcp_server_ids, enabled: true).custom_servers.filter_map do |server|
        next if server.url.blank?

        errors = UrlSafetyValidator.errors_for(server.url, require_https: server.auth_type_oauth?)
        "#{server.name} (#{errors.to_sentence})" if errors.any?
      end

      raise UnsafeMcpUrlError, "MCP server URL failed a safety check at launch: #{unsafe.join('; ')}" if unsafe.any?
    end

    def start_temporal_workflow(session)
      result = TemporalService.start_workflow(
        TemporalWorkflowRegistry.container_workflow,
        { session_id: session.id, manifest: session.strategy.build_manifest },
        id: session.workflow_id,
        execution_timeout: TerminalSession::WORKFLOW_TIMEOUT
      )
      raise result[:error] unless result[:ok]

      session.update!(
        temporal_workflow_id: result[:workflow_id],
        temporal_run_id: result[:run_id]
      )
    rescue StandardError => e
      Rails.logger.error("[SessionService] Failed to start workflow for session #{session.id}: #{e.message}")
      session.update!(error_message: "Failed to start workflow: #{e.message}")
      session.fail! if session.may_fail?
    end

    def signal_container_finished(session)
      result = TemporalService.send_signal(session.workflow_id, :container_finished, session.step_run&.id)

      if result.is_a?(Hash) && !result[:ok]
        error_msg = result[:error].to_s
        Rails.logger.warn("[SessionService] Signal failed for session #{session.id}: #{error_msg}")

        if error_msg.include?("already completed") || error_msg.include?("not found") || error_msg.include?("disabled")
          Rails.logger.warn("[SessionService] Temporal workflow gone, finishing session #{session.id} directly")
          finalize_finished(session)
        end
      end
    rescue StandardError => e
      Rails.logger.error("[SessionService] Failed to signal container_finished for session #{session.id}: #{e.message}")
      finalize_finished(session)
    end

    def finalize_finished(session)
      session.complete_finish!
    end

    def cancel_temporal_workflow(session)
      TemporalService.cancel_workflow(session.workflow_id)
    rescue StandardError => e
      Rails.logger.error("[SessionService] Failed to cancel workflow for session #{session.id}: #{e.message}")
    end

    def attach_resolved_resources(session, config)
      session.tools = scoped_resources(Tool, config[:tool_ids], session) if config[:tool_ids].present?
      session.skills = scoped_resources(Skill, config[:skill_ids], session) if config[:skill_ids].present?
      session.mcp_servers = scoped_resources(MCPServer, config[:mcp_server_ids], session) if config[:mcp_server_ids].present?
      session.repositories = scoped_resources(Repository, config[:repository_ids], session) if config[:repository_ids].present?
      session.input_assets = scoped_resources(Asset, config[:input_asset_ids], session) if config[:input_asset_ids].present?
    end

    # Resources resolve against the session's PROJECT company; project-less
    # sessions fall back to the user's first active membership's company.
    def scoped_resources(klass, ids, session)
      base = if session.project
               klass.visible_for_project(session.project)
      elsif klass.respond_to?(:visible_for_company)
               company = SessionCompany.company_for(session)
               company ? klass.visible_for_company(company) : klass.none
      else
               # Project-only resources (Skill, MCPServer) have nothing to attach
               # to a projectless session; internal MCP still arrives separately.
               klass.none
      end
      base.where(id: ids)
    end
  end
end
