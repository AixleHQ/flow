# frozen_string_literal: true

module Tools
  # Per-request evaluation context for tool availability and injection rules.
  # Batches the integration lookup into ONE query and memoizes it on the
  # context object itself — deliberately not CurrentAttributes: MCP requests
  # can outlive the Rack executor (SSE streams) and Temporal activity threads
  # never enter it, so object-scoped memoization is the only shape that can't
  # leak across requests.
  class Context
    attr_reader :project, :company, :session, :mode, :session_type
    attr_accessor :candidate_tools # set during the available_tools base phase

    def self.for_session(session)
      new(
        project: session.project,
        company: session.project&.company || session.user&.company,
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

    def connected_providers
      @connected_providers ||= begin
        if company.nil?
          Set.new
        else
          scope = Integration.active.where(company_id: company.id)
          scope = if project
            scope.where("project_id IS NULL OR project_id = ?", project.id)
          else
            scope.where(project_id: nil)
          end
          Set.new(scope.distinct.pluck(:provider).map(&:to_s))
        end
      end
    end
  end
end
