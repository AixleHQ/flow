# frozen_string_literal: true

module Activities
  module Tool
    class ExecuteContainerActivity < Base
      def run(input)
        tool = Tool.find(input.tool_id)
        project = input.project_id.present? ? Project.find(input.project_id) : nil

        strategy = ContainerStrategies::ToolExecutionStrategy.new(
          tool: tool,
          parameters: input.parameters || {},
          project: project,
          timeout: input.timeout
        )

        log(:info, "[ExecuteTool] Tool #{tool.id}")
        ContainerService.execute(strategy: strategy, input: strategy.input)
      rescue ContainerService::ExecutionError, ArgumentError => e
        raise TemporalExceptions.wrap(e, retryable: false)
      end
    end
  end
end
