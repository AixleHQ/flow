# frozen_string_literal: true

module Tools
  # Per-request evaluation context for tool availability and injection rules.
  # Batches the integration lookup into one query (plus one for trackers) and
  # memoizes it on the context object itself — deliberately not
  # CurrentAttributes: MCP requests can outlive the Rack executor (SSE streams)
  # and Temporal activity threads never enter it, so object-scoped memoization
  # is the only shape that can't leak across requests.
  class Context
    attr_reader :project, :company, :session, :mode, :session_type
    attr_accessor :candidate_tools # set during the available_tools base phase

    def self.for_session(session)
      new(
        project: session.project,
        company: SessionCompany.company_for(session),
        session: session,
        mode: session.mode,
        session_type: session.session_type
      )
    end

    # Pickers / config resolution: no session yet.
    def self.for_project(project)
      new(project: project, company: project.company)
    end

    def initialize(project:, company:, session: nil, mode: nil, session_type: nil)
      @project = project
      @company = company
      @session = session
      @mode = mode
      @session_type = session_type
      @candidate_tools = []
    end

    def connected?(provider)
      connected_providers.include?(provider.to_s)
    end

    # The providers a tool's `requires_integration` is checked against. With a session it is
    # the providers of the session's own integration set (docs/design/session-integrations.md
    # §5.3), so a tool is served only when its provider's integration is attached to the
    # session. Without one (pickers, project pages) it stays project-wide, so a tool can still
    # be attached.
    def connected_providers
      @connected_providers ||= begin
        if company.nil?
          Set.new
        else
          providers = Set.new(session ? session_providers : project_providers)
          providers << Trackers::CAPABILITY if project && ProjectTracker.usable.for_project(project).exists?
          providers << Chat::CAPABILITY if providers.intersect?(Chat::PROVIDERS.keys.to_set)
          providers << PullRequests::CAPABILITY if providers.intersect?(PullRequests::PROVIDERS.keys.to_set)
          providers
        end
      end
    end

    # What to tell a session caller whose tool was refused for `provider`: set only when the
    # provider's integration is connected to the project but not in the session's set, where
    # "connect it in Project Settings" would not fix the call. Nil otherwise (no session, or
    # nothing connected), so the caller keeps the connection guidance.
    def attach_message(provider)
      return nil if session.nil? || company.nil? || provider.blank?
      return nil if connected?(provider) || !project_connected?(provider)

      "The #{provider} integration is not attached to this session. " \
        "Attach it to the workflow, the step or the session."
    end

    private

    # The project-wide counterpart of `connected?`, with the same capability expansion.
    def project_connected?(provider)
      @project_connected ||= begin
        providers = Set.new(project_providers)
        providers << Chat::CAPABILITY if providers.intersect?(Chat::PROVIDERS.keys.to_set)
        providers << PullRequests::CAPABILITY if providers.intersect?(PullRequests::PROVIDERS.keys.to_set)
        providers
      end
      @project_connected.include?(provider.to_s)
    end

    def project_providers
      scope = Integration.active.where(company_id: company.id)
      scope = if project
        scope.where("project_id IS NULL OR project_id = ?", project.id)
      else
        scope.where(project_id: nil)
      end
      scope.distinct.pluck(:provider).map(&:to_s)
    end

    # One query, memoized on the context with the rest of the answer.
    def session_providers
      session.integrations.active.distinct.pluck(:provider).map(&:to_s)
    end
  end
end
