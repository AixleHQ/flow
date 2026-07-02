# frozen_string_literal: true

module InternalTools
  class Base
    extend Tools::DefinitionDSL

    attr_reader :params, :session, :mcp_server

    def initialize(params:, session:, mcp_server: nil)
      @params = params.with_indifferent_access
      @session = session
      @mcp_server = mcp_server
    end

    def execute
      raise NotImplementedError, "#{self.class}#execute must be implemented"
    end

    private

    def project
      session&.project
    end

    def step_run
      session&.step_run
    end

    def workflow_run
      step_run&.workflow_run
    end

    def require_workflow_context!
      raise WorkflowContextError, "This tool requires a workflow context (no step_run on session)" unless step_run
    end

    def success(text)
      { exit_code: 0, stdout: text.to_s, stderr: "" }
    end

    def error(text)
      { exit_code: 1, stdout: "", stderr: text.to_s }
    end
  end
end
