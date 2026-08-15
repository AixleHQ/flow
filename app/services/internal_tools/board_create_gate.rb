# frozen_string_literal: true

module InternalTools
  class BoardCreateGate < Base
    tool do
      display_name "Board Create Gate"
      description "Create a Gate on a board task. The auto-workflow for the task's column will not fire until all " \
                  "Gates are resolved. A Gate is TTL-bounded: if its CI webhook never arrives, a periodic sweep asks " \
                  "the provider about the recorded repository and run/check id and resolves the Gate with the real " \
                  "verdict, or marks it stale with a diagnostic reason once it is unreadable or past its TTL."
      tags :board
      inject_when :workflow_step_session
      input_schema({
        type: "object",
        required: %w[task_id gate_type],
        properties: {
          run_id: {
            type: "integer",
            description: "(github_workflow_completed) GitHub Actions workflow run ID"
          },
          task_id: {
            type: "integer",
            description: "Board task ID"
          },
          gate_type: {
            type: "string",
            description: "Gate type. Supported: github_checks_completed, github_workflow_completed"
          },
          pr_number: {
            type: "integer",
            description: "(github_checks_completed) Pull request number"
          },
          repo_full_name: {
            type: "string",
            description: "(github_checks_completed, github_workflow_completed) Full repo name, e.g. owner/repo"
          }
        }
      })
    end

    SUPPORTED_GATE_TYPES = %w[github_checks_completed github_workflow_completed gitlab_pipeline_completed].freeze

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      gate_type = params[:gate_type]
      return error("Unsupported gate_type: #{gate_type}") unless SUPPORTED_GATE_TYPES.include?(gate_type)

      metadata = build_metadata(gate_type, task)
      return metadata if metadata.is_a?(Hash) && metadata.key?(:exit_code)

      gate = task.gates.create!(gate_type: gate_type, metadata: metadata, creator: workflow_run.user)

      success({
        id:         gate.id,
        task_id:    task.id,
        gate_type:  gate.gate_type,
        status:     gate.status,
        metadata:   gate.metadata,
        # When this Gate stops waiting on CI whatever happens, so a step that parks
        # a task can say how long the wait can last.
        expires_at: gate.expires_at
      }.to_json)
    end

    private

    def build_metadata(gate_type, task)
      case gate_type
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

  # Backward compatibility: the tool was historically named "board_create_wait".
  # InternalToolExecutor resolves "board_create_wait".camelize → BoardCreateWait,
  # so keep that constant pointing at the renamed class for any Tool record or
  # workflow instruction that still uses the old name.
  BoardCreateWait = BoardCreateGate
end
