# frozen_string_literal: true

module Activities
  module Tool
    class PullImageActivity < Base
      def run(input)
        tool = Tool.find(input.tool_id)
        strategy = ContainerStrategies::ToolExecutionStrategy.new(tool: tool)

        log(:info, "[PullTool] Image for tool #{tool.id}")
        strategy.pull_image
      rescue Docker::Error::NotFoundError => e
        raise TemporalExceptions.wrap(e, retryable: false)
      rescue Docker::Error::DockerError => e
        raise TemporalExceptions.wrap(e, retryable: true)
      end
    end
  end
end
