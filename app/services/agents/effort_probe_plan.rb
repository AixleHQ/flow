# frozen_string_literal: true

module Agents
  # Every launch with a reasoning effort that a company member's model pickers offer for one
  # runtime: each model the member's credential lists, with each level the registry offers
  # for it, as the adapter types it into a step's pane. bin/agent-effort-probe runs them
  # inside a session container of that runtime, so a level the CLI refuses is found before
  # a step meets it (task #324: Cursor CLI exited on `composer-2.5[effort=low]`).
  #
  # A runtime that takes the level from a config file rather than the command line (Gemini
  # CLI's settings.json) cannot be varied per launch inside one container; its rows say so.
  #
  # `plain: true` adds each model's launch without a level, for the runtimes whose model id
  # carries the effort (Cursor CLI, Antigravity CLI): there the model list itself is what
  # can drift from what the CLI accepts.
  class EffortProbePlan
    def self.for(membership, agent_type, plain: false)
      new(membership, agent_type.to_s, plain: plain).rows
    end

    def initialize(membership, agent_type, plain: false)
      @membership = membership
      @agent_type = agent_type
      @plain = plain
    end

    def rows
      offered_models.flat_map do |model|
        levels = model[:reasoning_effort_levels]
        levels = [ nil, *levels ] if plain
        levels.map { |level| row(model[:model_id], level) }
      end
    end

    private

    attr_reader :membership, :agent_type, :plain

    def offered_models
      entry = membership.agent_models_for_props.find { |models| models[:agent_type] == agent_type }
      entry ? entry[:models] : []
    end

    def row(model, level)
      command = launch(model, level)
      { agent_type: agent_type, model: model, effort: level, command: command,
        on_command_line: level.nil? || command != launch(model, nil) }
    end

    def launch(model, level)
      adapter.session_command(mode: "non_interactive", model: model, effort: level)
    end

    def adapter
      @adapter ||= AgentCredentialsService.for(agent_type).adapter
    end
  end
end
