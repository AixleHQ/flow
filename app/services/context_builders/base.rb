# frozen_string_literal: true

module ContextBuilders
  class Base
    attr_reader :session

    def initialize(session)
      @session = session
    end

    def build
      raise NotImplementedError, "#{self.class}#build must be implemented"
    end

    def applicable?
      true
    end

    def name
      self.class.name.demodulize.underscore
    end

    private

    def section(tag:, priority:, content:, position_hint: :middle)
      ContextSection.new(tag: tag, priority: priority, content: content, position_hint: position_hint, builder_name: name)
    end

    def project
      session.project
    end

    def step_run
      session.step_run
    end

    def workflow_run
      step_run&.workflow_run
    end

    def workflow
      workflow_run&.workflow
    end

    def board_task
      workflow_run&.board_task
    end

    def step
      step_run&.step
    end
  end
end
