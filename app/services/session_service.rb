# frozen_string_literal: true

class SessionService
  # Raised at session-start when a selected custom MCP server's URL fails a
  # safety re-check (F34): the URL is validated at create/update, but DNS or the
  # stored value may have changed since, so we re-check before dialing.
  class UnsafeMcpUrlError < StandardError; end

  # What a launch preflight refuses with: something the session's user has to
  # renew or fix, and is told about on the session.
  PREFLIGHT_REFUSALS = [
    Oauth::PreflightError, CloudAuth::PreflightError, AgentCredential::PreflightError, UnsafeMcpUrlError
  ].freeze

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
      credential = preflight_agent_credential!(user, company || project&.company, agent_type, session_type: session_type)
      preflight_model!(credential, params[:requested_model])
      preflight_url_safety!(params[:mcp_server_ids])
      preflight_company_active!(company || project&.company)

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
        **params.slice(:mode, :initial_prompt, :requested_model, :reasoning_effort, :session_config,
                       :tool_ids, :skill_ids, :mcp_server_ids, :input_asset_ids, :repository_ids,
                       :config_item_ids, :integration_ids, :runner_id, :restored_from_session_id)
      )

      return session if refuse_runner_pick(session, params)
      return session unless session.save
      return session if fail_on_runner_refusal(session)

      attach_derived_integrations(session)
      Versions::LaunchRecord.record!(session)
      # The writer lock is taken around the queue write only — never around the
      # save, which touches half a dozen join tables.
      Sessions::Lifecycle.enqueue(session)
      launch_session(session)

      session
    end

    # Starts the session that continues a suspended one. A restore already on its way is
    # returned instead of a second one; one that failed can be tried again.
    def restore(session:, user:)
      raise TerminalSession::InvalidStateError, "This session cannot be restored" unless session.user_id == user.id

      # Before the check below: a step's suspended session stops being its current one
      # as soon as the restore is under way.
      pending = TerminalSession.where(restored_from_session_id: session.id).where.not(state: %w[failed cancelled]).first
      return pending if pending
      raise TerminalSession::InvalidStateError, "This session cannot be restored" unless Sessions::Suspension.restorable?(session)
      return restore_step(session) if session.workflow_step?

      create_and_start(user: user, project: session.project, session_type: "agent_session",
                       agent_type: session.agent_type, configured_agent: session.configured_agent,
                       params: Sessions::Restore.params_for(session))
    end

    # A step's new session is built as the step's sessions always are, from the step and
    # its run, and becomes the step's current one: the run, which reads the step's current
    # session, moves on when this one ends. The suspended one stays reachable through
    # `restored_from_session`.
    def restore_step(origin)
      step_run = origin.step_run
      session = ActiveRecord::Base.transaction do
        step_run.lock!
        unless step_run.terminal_session_id == origin.id && step_run.suspended?
          raise TerminalSession::InvalidStateError, "This step has moved on"
        end

        build_for_workflow_step(step_run: step_run).tap do |built|
          built.update!(restored_from_session: origin)
          # The step's links may have changed while the session was suspended; its set did not.
          built.integrations = scoped_integrations(Sessions::Restore.integration_ids_for(origin), built)
          step_run.update!(state: :running)
        end
      end
      admit_step_session!(step_run, session)
      launch_session(session)
      session
    end

    # `refresh_tokens:` is set on the one call that precedes an actual launch.
    # The per-phase calls only re-check authorization; refreshing on every phase
    # would put a token round-trip in front of each container step.
    def revalidate_admission!(session, refresh_tokens: false)
      SessionAdmissionService.ensure_run_active!(session)
      raise SessionAdmissionService::Stopped, "User account unavailable" unless session.user&.authenticatable?
      if session.project && !session.project.accessible_by?(session.user)
        raise SessionAdmissionService::Stopped, "Project access revoked"
      end
      if session.company_id && !CompanyMembership.active.exists?(company_id: session.company_id, user_id: session.user_id)
        raise SessionAdmissionService::Stopped, "Company membership revoked"
      end
      preflight_company_active!(SessionCompany.company_for(session))
      if !session.auth_setup? && session.session_credential.nil?
        raise SessionAdmissionService::Stopped, "Agent credential unavailable"
      end
      preflight_oauth!(session.user, session.mcp_server_ids)
      preflight_cloud!(session.user, SessionCompany.company_for(session))
      # Checked again here and not only at create: the refresh sweep can mark a
      # credential errored while the session is still waiting in the queue. The
      # session_type carries the auth_setup exemption — a login session exists to
      # replace the broken credential, so gating it on that credential would trap
      # the user behind the queue with no way out.
      preflight_agent_credential!(session.user, SessionCompany.company_for(session), session.agent_type,
        session_type: session.session_type, excluding_session_id: session.id)
      preflight_url_safety!(session.mcp_server_ids)
      refresh_oauth_tokens_for_session(session) if refresh_tokens
    end

    # Built first and admitted second, in separate transactions. Building renders
    # the instructions and attaches every resolved resource, and doing that under
    # the installation-wide writer lock stalled every other admission decision for
    # up to 20 s (PALAD-AI-RAILS-2Z). The step_run row lock is what keeps a retried
    # launch from building twice; the run is re-checked under the writer lock,
    # which is where a cancel writes its stop marker.
    def create_for_workflow_step(step_run:)
      session = ActiveRecord::Base.transaction do
        step_run.lock!
        step_run.terminal_session || begin
          run = step_run.workflow_run
          raise SessionAdmissionService::Stopped, "Workflow cancelled" if run.stopped?
          preflight_company_active!(run.project&.company)
          # Before the build, like the credential preflight: a refused runner
          # leaves no session behind (LaunchStepSessionActivity fails the step).
          Runners::Resolver.resolve!(run)
          build_for_workflow_step(step_run: step_run)
        end
      end
      return session if session.session_admission

      admit_step_session!(step_run, session)
      launch_session(session)
      session
    end

    def build_for_workflow_step(step_run:)
      workflow_run = step_run.workflow_run
      step = step_run.step

      instructions = InstructionReferences::Renderer.new(step: step, project: workflow_run.project).render(step.instructions)
      prompt = instructions.presence || "Execute step: #{step.name}"
      runtime = step.required_agent_runtime.presence ||
                workflow_run.agent_runtime.presence ||
                run_membership(workflow_run)&.default_agent_runtime.presence ||
                run_credentials(workflow_run).order(created_at: :desc).first&.agent_type ||
                "claude_code"

      credential = preflight_agent_credential!(workflow_run.user, workflow_run.project&.company, runtime)

      run_model = workflow_run.shared_context&.dig("requested_model")
      preflight_model!(credential, step.preferred_model.presence || run_model)

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
        reasoning_effort: step.reasoning_effort,
        runner_id: workflow_run.runner_id,
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
      Versions::LaunchRecord.record!(session, step_run: step_run)
      session
    end

    private

    # A runner picked on the new-session form or in the API (DESIGN.md §3.3);
    # without one the session is hosted.
    def refuse_runner_pick(session, params)
      return false unless params.key?(:runner_id)
      return false if params[:runner_id].blank? && session.project.nil?

      kind, error = if session.project.nil?
        [ :project_required, "Runner can only be picked for a project's session." ]
      else
        Runners::Selection.refusal(params[:runner_id], project: session.project)
      end
      # The kind rides on the error so the API can tell a runner the project may not use (403) from the rest (422).
      session.errors.add(:base, kind, message: error) if error
      error.present?
    end

    # Saved, then failed before admission: the session page shows the message.
    def fail_on_runner_refusal(session)
      Runners::Resolver.resolve!(session, pick_from: "for the session")
      false
    rescue Runners::Resolver::Refused => e
      Sessions::Lifecycle.fail(session, error_message: e.message)
      true
    end

    # A run stopped between the build and this point leaves a session nobody
    # will launch; the cancel fan-out skips it, since it has no admission to close.
    def admit_step_session!(step_run, session)
      SessionAdmissionService.transaction do
        step_run.workflow_run.lock!
        Sessions::Lifecycle.enqueue(session)
      end
    rescue SessionAdmissionService::Stopped
      Sessions::Lifecycle.cancel(session.reload)
      raise
    end

    # Granting is cheap and must happen now so the caller sees a real queue
    # position. Dispatching is not: it costs a preflight and a Temporal RPC per
    # session, so this hands off only THIS session and leaves the rest of the
    # newly granted batch to the relay running in the reconciler.
    def launch_session(session)
      SessionAdmissionService.drain!
      admission = session.session_admission.reload
      SessionLaunchRelay.dispatch(admission) if admission.admitted_at && admission.launch_state == "pending"
    end

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

      # Proactively refresh tokens expiring within 1 hour so inject_oauth_token!
      # (one-shot at provisioning) gets a token valid for the session's lifetime.
      servers.each do |server|
        next unless server.auth_type_oauth?

        owner = server.credential_scope_per_user? ? user : server.scope
        next if owner.nil?

        cred = OauthCredential.current_for(server: server, owner: owner)
        next if cred.nil?

        Oauth::TokenService.refresh_if_expiring_soon(cred)
        cred.reload
        if cred.error?
          raise Oauth::PreflightError, [ { mcp_server_id: server.id, name: server.name, reason: :credential_error,
                                           connect_url: "/oauth/mcp/#{server.id}/connect", connect_method: "post" } ]
        end
      end
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

    # Block a launch whose agent credential is missing, or that the refresh sweep
    # has marked broken, so the user gets "connect an agent" / "sign in again"
    # instead of a session revalidate_admission! cancels or a container that fails
    # on an expired token.
    #
    # An auth_setup session is exempt: it exists to REPLACE the broken credential,
    # so gating it on that credential locks the user out of the only flow that can
    # clear the error.
    # `excluding_session_id:` is the session being launched. It is itself an active row,
    # so without it the "is another container holding these tokens?" test would find this
    # session and refuse every launch it was asked to check.
    def preflight_agent_credential!(user, company, agent_type, session_type: nil, excluding_session_id: nil)
      return if TerminalSession.auth_setup_type?(session_type)
      return unless agent_type.present? && company.present?

      credentials = AgentCredential.where(user_id: user.id, company_id: company.id)
      credential = credentials.find_by(agent_type: agent_type)
      if credential.nil?
        raise AgentCredential::PreflightError.new(agent_type: (agent_type if credentials.exists?))
      end

      raise AgentCredential::PreflightError, credential unless credential.active?
      # An `active` row is not the same as a usable login: a credential whose token died
      # while a live session pinned it out of the refresh sweep never records an error,
      # because no refresh was ever attempted. Launching on it produces a container that
      # prints "Login expired" and nothing else.
      raise AgentCredential::PreflightError, credential if credential.unrecoverably_expired?(excluding_session_id: excluding_session_id)

      credential
    end

    # Some CLIs, asked for a model their account does not offer, quietly run their default
    # model (task #324: Antigravity CLI and Grok did, with no error anywhere a person would
    # look). For those the model is looked up in the account's catalogue before anything
    # starts, and only a catalogue the vendor answered counts: a fallback list says nothing
    # about the account, and an unreachable one must not stop a launch.
    def preflight_model!(credential, model)
      return if credential.nil? || model.blank?

      adapter = AgentCredentialsService.for(credential.agent_type).adapter
      return unless adapter.runs_default_model_for_unknown?

      catalogue = adapter.fetch_available_models_with_source(credential.config_data, credential: credential)
      return unless catalogue[:source] == :api

      offered = Array(catalogue[:models]).pluck(:model_id)
      raise AgentCredential::ModelUnavailable.new(credential, model, offered) unless offered.include?(model)
    end

    # Re-validate selected custom MCP server URLs right before launch (F34). The
    # model validates at create/update, but DNS (rebinding) or the stored value
    # may have changed since — a host that now resolves to a private/internal IP
    # must not be dialed. Cheap: url_safety uses local resolvers only.
    # A suspended or archived company runs nothing. Checked at creation and again
    # on every phase, because a company suspended while a session is queued or
    # running has to stop that session too — the same shape as a revoked
    # membership, and the relay turns it into a cancellation the owner can read.
    #
    # Metering leans on this: Billing::CapacityWindow bills only active
    # companies, which is only honest while they are also the only ones that can
    # occupy a slot.
    def preflight_company_active!(company)
      return if company.nil? || company.active?

      raise SessionAdmissionService::Stopped, "Company #{company.name} is #{company.state} and cannot run sessions"
    end

    def preflight_url_safety!(mcp_server_ids)
      return if mcp_server_ids.blank?

      unsafe = MCPServer.where(id: mcp_server_ids, enabled: true).custom_servers.filter_map do |server|
        next if server.url.blank?

        errors = UrlSafetyValidator.errors_for(server.url, require_https: server.auth_type_oauth?)
        "#{server.name} (#{errors.to_sentence})" if errors.any?
      end

      raise UnsafeMcpUrlError, "MCP server URL failed a safety check at launch: #{unsafe.join('; ')}" if unsafe.any?
    end

    def refresh_oauth_tokens_for_session(session)
      session.mcp_servers.each do |server|
        next unless server.auth_type_oauth?

        owner = server.credential_scope_per_user? ? session.user : server.scope
        next if owner.nil?

        cred = OauthCredential.current_for(server: server, owner: owner)
        next if cred.nil?

        if cred.error?
          raise Oauth::PreflightError, [ { mcp_server_id: server.id, name: server.name, reason: :credential_error,
                                           connect_url: "/oauth/mcp/#{server.id}/connect", connect_method: "post" } ]
        end

        Oauth::TokenService.refresh_if_expiring_soon(cred)
        cred.reload
        if cred.error?
          raise Oauth::PreflightError, [ { mcp_server_id: server.id, name: server.name, reason: :credential_error,
                                           connect_url: "/oauth/mcp/#{server.id}/connect", connect_method: "post" } ]
        end
      end
    end

    def attach_resolved_resources(session, config)
      session.tools = scoped_resources(Tool, config[:tool_ids], session) if config[:tool_ids].present?
      session.skills = scoped_resources(Skill, config[:skill_ids], session) if config[:skill_ids].present?
      session.mcp_servers = scoped_resources(MCPServer, config[:mcp_server_ids], session) if config[:mcp_server_ids].present?
      session.repositories = scoped_resources(Repository, config[:repository_ids], session) if config[:repository_ids].present?
      session.input_assets = scoped_resources(Asset, config[:input_asset_ids], session) if config[:input_asset_ids].present?
      session.integrations = scoped_integrations(config[:integration_ids], session) if config[:integration_ids].present?
    end

    # An interactive or API session starts with the integrations it was given. What its
    # repositories bring with them is added here, once they are attached.
    def attach_derived_integrations(session)
      ids = SessionConfigResolver.new(session).resolve_integration_ids
      session.integrations = scoped_integrations(ids, session) if ids.present?
    end

    # Ownership, not what a picker offers: a company-wide integration stays attachable.
    def scoped_integrations(ids, session)
      TenantScope.owned(Integration, project: session.project, company: SessionCompany.company_for(session)).where(id: ids)
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
