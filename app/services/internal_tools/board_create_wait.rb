# frozen_string_literal: true

module InternalTools
  class BoardCreateWait < Base
    SUPPORTED_WAIT_TYPES = %w[github_checks_completed github_workflow_completed gitlab_pipeline_completed].freeze

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      wait_type = params[:wait_type]
      return error("Unsupported wait_type: #{wait_type}") unless SUPPORTED_WAIT_TYPES.include?(wait_type)

      metadata = build_metadata(wait_type, task)
      return metadata if metadata.is_a?(Hash) && metadata.key?(:exit_code)

      wait = task.task_waits.create!(wait_type: wait_type, metadata: metadata, creator: workflow_run.user)

      success({
        id:        wait.id,
        task_id:   task.id,
        wait_type: wait.wait_type,
        status:    wait.status,
        metadata:  wait.metadata
      }.to_json)
    end

    private

    def build_metadata(wait_type, task)
      case wait_type
      when "github_checks_completed"
        repo_full_name = params[:repo_full_name]
        pr_number      = params[:pr_number].to_i

        return error("repo_full_name is required") if repo_full_name.blank?
        return error("pr_number must be a positive integer") unless pr_number > 0

        project = task.board.project
        unless Repository.visible_for_project(project).where(full_name: repo_full_name).exists?
          return error("Repository #{repo_full_name} is not linked to this task's project")
        end

        { repo_full_name: repo_full_name, pr_number: pr_number }

      when "github_workflow_completed"
        repo_full_name = params[:repo_full_name]
        run_id         = params[:run_id].to_i

        return error("repo_full_name is required") if repo_full_name.blank?
        return error("run_id must be a positive integer") unless run_id > 0

        project = task.board.project
        unless Repository.visible_for_project(project).where(full_name: repo_full_name).exists?
          return error("Repository #{repo_full_name} is not linked to this task's project")
        end

        { repo_full_name: repo_full_name, run_id: run_id }

      when "gitlab_pipeline_completed"
        repo_full_name = params[:repo_full_name]
        pipeline_id    = params[:pipeline_id].to_i

        return error("repo_full_name is required") if repo_full_name.blank?
        return error("pipeline_id must be a positive integer") unless pipeline_id > 0

        project = task.board.project
        unless Repository.visible_for_project(project).where(full_name: repo_full_name).exists?
          return error("Repository #{repo_full_name} is not linked to this task's project")
        end

        { repo_full_name: repo_full_name, pipeline_id: pipeline_id }
      end
    end
  end
end
