# frozen_string_literal: true

module Activities
  module Tool
    class CleanupContainerActivity < Base
      def run(input)
        container_id = input.container_id
        runtime = ContainerRuntime.build

        log(:info, "[CleanupTool] Container #{container_id}")

        begin
          runtime.stop_container(container_id, 5)
        rescue StandardError => e
          log(:warn, "[CleanupTool] Stop failed: #{e.message}")
        end

        begin
          runtime.remove_container(container_id)
          { status: :cleaned_up, container_id: container_id }
        rescue StandardError => e
          log(:warn, "[CleanupTool] Remove failed: #{e.message}")
          { status: :failed, container_id: container_id, error: e.message }
        end
      end
    end
  end
end
