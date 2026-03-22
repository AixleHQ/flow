# frozen_string_literal: true

module InternalTools
  class BoardCreateWait < Base
    SUPPORTED_WAIT_TYPES = %w[github_checks_completed].freeze

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      wait_type = params[:wait_type]
      return error("Unsupported wait_type: #{wait_type}") unless SUPPORTED_WAIT_TYPES.include?(wait_type)

      metadata = build_metadata(wait_type)
      return metadata if metadata.is_a?(Hash) && metadata.key?(:exit_code)

      wait = task.task_waits.create!(wait_type: wait_type, metadata: metadata)

      success({
        id:        wait.id,
        task_id:   task.id,
        wait_type: wait.wait_type,
        status:    wait.status,
        metadata:  wait.metadata
      }.to_json)
    end

    private

    def build_metadata(wait_type)
      case wait_type
      when "github_checks_completed"
        repo_full_name = params[:repo_full_name]
        pr_number      = params[:pr_number].to_i

        return error("repo_full_name is required") if repo_full_name.blank?
        return error("pr_number must be a positive integer") unless pr_number > 0

        { repo_full_name: repo_full_name, pr_number: pr_number }
      end
    end
  end
end
